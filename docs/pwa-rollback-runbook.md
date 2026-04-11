# COOL Admin PWA — Rollback & Cache-Busting Runbook

## Service Worker Architecture

The COOL Admin PWA uses a versioned service worker (`service-worker.js`) with three
named caches:

| Cache | Strategy | Content |
|-------|----------|---------|
| `cool-pwa-v{N}-precache` | Install-time | Shell routes + core assets |
| `cool-pwa-v{N}-runtime` | Stale-while-revalidate | CSS, JS, images, fonts |
| `cool-pwa-v{N}-data` | Network-first | `/data/*.json` |

When `VERSION` changes, the **activate** handler deletes all caches that don't
match the current version. The **update banner** appears when a new service
worker is installed and waiting.

---

## Standard Rollback (< 5 minutes)

### 1. Revert via Cloudflare Pages Dashboard

1. Open **Cloudflare Dashboard → Pages → cool → Deployments**.
2. Find the last known-good production deployment.
3. Click **Rollback to this deployment**.
4. This is instant — Cloudflare serves the previous build immediately.

### 2. Bump Service Worker VERSION

After the rollback deploy, the old `service-worker.js` still has the **same**
VERSION as the broken deploy. To force cache refresh:

1. In the reverted source, bump `VERSION` in `service-worker.js`:
   ```diff
   -const VERSION = 'cool-pwa-v5';
   +const VERSION = 'cool-pwa-v6';
   ```
2. Push to `main` → CI deploys the version-bumped build.

### 3. Client-Side Recovery

- **Automatic:** Users with the PWA open will see the "Updated" banner within
  5 minutes (service worker check interval). Clicking "Refresh" activates the
  new worker and clears stale caches.
- **Manual:** Users can hard-refresh (Ctrl+Shift+R / ⌘+Shift+R) to bypass the
  service worker.

---

## Emergency Rollback (broken service worker)

If the service worker itself is broken (infinite loops, registration failures):

### Option A: Deploy a no-op service worker

Create a `service-worker.js` that immediately self-destructs:

```javascript
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', async () => {
  const names = await caches.keys();
  await Promise.all(names.map((name) => caches.delete(name)));
  await self.clients.claim();
  const clients = await self.clients.matchAll({ type: 'window' });
  clients.forEach((client) => client.navigate(client.url));
});
```

### Option B: Add Clear-Site-Data header

In `_headers` or via `functions/index.js`, add temporarily:

```
Clear-Site-Data: "cache", "storage"
```

> [!CAUTION]
> This clears ALL site data including IndexedDB and localStorage. Remove the
> header after one deployment cycle.

---

## Verification After Rollback

1. Open the deployed URL in an incognito window.
2. Check that `/admin/` loads without errors.
3. Open DevTools → Application → Service Workers:
   - Verify the expected VERSION is active.
   - Verify no workers are "waiting" or in error state.
4. Check DevTools → Application → Cache Storage:
   - Only caches matching the current VERSION should exist.
5. Run: `SMOKE_URL=https://cool.ikanisa.com node scripts/post-deploy-smoke.mjs`

---

## Prevention

- Always bump `VERSION` in `service-worker.js` when changing the precache
  manifest (added/removed assets, route changes).
- Test service worker updates locally:
  ```bash
  npx wrangler pages dev . --port 4173
  ```
- CI runs Lighthouse which validates service worker registration.
