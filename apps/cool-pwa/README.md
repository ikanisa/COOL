# COOL Admin PWA

Standalone Progressive Web App for COOL admin operations, added alongside the
maintained Flutter client.

This app is intentionally separate from the Flutter codebase:

- Flutter mobile remains the primary end-user client.
- `apps/cool-pwa` is now an admin-only web control plane.
- The PWA ships as static clean-URL admin pages with a shared app shell,
  offline queueing, install UX, operational alerts, and browser-audit scripts.

## Local Run

```bash
cd apps/cool-pwa
npm install
npm run serve          # Static preview (no Pages Functions)
```

Open `http://127.0.0.1:4173/admin/`.

For live backend (Pages Functions + Supabase):

```bash
cd apps/cool-pwa
npx wrangler pages dev . --port 4173
```

## Verification

```bash
npm test                    # Contract + browser tests
npm run audit:lighthouse    # Lighthouse perf/a11y/best-practices
npm run test:integration    # Pages Functions integration suite (requires wrangler)
```

## Deploy

**Deployment target: Cloudflare Pages** (canonical — no Firebase hosting).

```bash
cd apps/cool-pwa
npx wrangler pages deploy
```

Production domains rewrite `/` to `/admin/` so the admin workspace is
the only entrypoint.

### Cloudflare-specific files

| File | Purpose |
|------|---------|
| `wrangler.toml` | Pages project config |
| `_headers` | Security + caching headers |
| `functions/index.js` | Root redirect + security header injection |
| `functions/api/auth/` | OTP auth + session cookie management |
| `functions/api/admin/` | Data, session, and mutation endpoints |

### Environment Variables (Pages Functions)

| Variable | Scope | Required |
|----------|-------|----------|
| `COOL_PROJECT_SUPABASE_URL` | Pages Functions | Yes |
| `COOL_PROJECT_SUPABASE_ANON_KEY` | Pages Functions | Yes |
| `COOL_PROJECT_SUPABASE_SERVICE_ROLE_KEY` | Pages Functions | Yes (admin phone pre-check) |

Set these in the Cloudflare Pages dashboard under **Settings → Environment variables**.
Both preview and production environments need them.

### Rollback

See [pwa-rollback-runbook.md](../../docs/pwa-rollback-runbook.md) for the
service-worker-aware rollback and cache-busting procedure.
