# Human Review and External Blockers

## Current

1. Store signing, TestFlight/App Store upload, Google Play upload, and public
   deployment are not authorized by the current goal.
2. Production Supabase changes and live payment execution are not authorized.
3. Additional user-assisted phone scrolling may be required for lower
   Payments, Profile, Security, authentication, and transfer-state references.
4. The iOS release owner must enable Associated Domains for the controlled
   `app.cool.mobile` App ID and provide/select a compatible provisioning
   profile before a signed distribution archive can pass.
5. The complete local Admin PWA release wrapper and artifact manifest pass with
   the public `COLLECT_ADMIN_WHATSAPP_PHONE=250795588248` value. Deployment is
   not authorized, and the current live host still serves stale icon/service-
   worker output, so live-host refresh and post-deploy verification remain
   external.
6. Play Developer Reporting needs authorized OAuth/gcloud access, and the
   remaining Play Console surfaces require an account owner to inspect them.
7. Android signing review and release-owner approval must be freshly recorded
   for version `1.2.2+10`; existing approvals are tied to `1.2.2+9` and are now
   rejected by both the approval evidence gate and aggregate release status.

## Closure rule

These items do not block local implementation and testing. They block only the
corresponding external release or reference-dependent conclusion. No external
action will be inferred from local engineering readiness.
