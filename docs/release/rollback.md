# Rollback

Rollback in production-only mode must be planned before deployment. Prefer reversible feature flags and forward fixes over destructive database restore. Use restore only when data integrity or customer safety requires it.

## Rollback owners

- Release lead: decides rollback versus forward fix.
- Database operator: controls migration apply, backup, restore, and data repair.
- Web owner: redeploys admin and website artifacts.
- Mobile owner: controls phased rollout, store halt, or previous version guidance.
- Incident lead: coordinates communications and evidence preservation.

## Web rollback

1. Stop new deployment or disable traffic if deploy is still in progress.
2. Redeploy the previous known-good artifact from CI/provider history.
3. Confirm admin login, key dashboards, website legal pages, and account deletion route.
4. Keep audit and error evidence for incident review.

## Mobile rollback

- Use phased rollout controls to halt rollout if available.
- If a bad version is live, prepare a patched build with incremented version metadata.
- For server-driven defects, disable the affected feature through app config or backend permission checks when safe.
- Do not rely on users downgrading manually.

## Supabase rollback

1. Confirm backup/restore point from immediately before migration apply.
2. Identify whether a forward fix is safer than restore.
3. For schema-only additive migrations, prefer a forward migration that disables or corrects behavior.
4. For data corruption or unsafe permission exposure, freeze affected writes, preserve audit evidence, and restore or repair under operator approval.
5. Record migration ids, affected tables/functions, commands, operator, timestamps, and validation results.

## Edge Function rollback

1. Redeploy the last known-good function version if provider history allows it.
2. If rollback is unavailable, deploy a minimal fail-closed patch that rejects unsafe actions with a generic error.
3. Confirm auth, validation, rate limiting, and safe logging still work.

## Feature flag rollback

Use app config/feature flags for fast containment when available:

- Disable new payment guidance or manual allocation path.
- Disable campaign sending or require approval-only mode.
- Disable BioPay enrollment/match while preserving account access.
- Disable risky admin write surfaces while keeping read-only support access.

## Rollback verification

```bash
npm --prefix apps/admin run smoke:admin-browser
npm --prefix apps/admin run smoke:admin-search
npm --prefix apps/website run build
bash scripts/migrations/validate_supabase_migrations.sh
scripts/dev/flutterw test --concurrency=4 test/integration_smoke
```

After rollback, open an incident review with timeline, customer impact, data impact, audit evidence, root cause, corrective actions, and follow-up owner.
