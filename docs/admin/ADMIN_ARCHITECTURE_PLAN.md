# Collect Admin architecture

Updated 20 November 2026.

Collect operates one React web Admin. The panel serves operators and owners. Collect members use the Flutter app. Field staff and receiver operators use the native BuriMunsi Staff and Admin Sync apps.

## Browser and server

| Responsibility | Implementation |
| --- | --- |
| Startup and navigation | The React entrypoint restores the session and opens the hash router. Existing path-style Admin bookmarks resolve to their corresponding route. The app shell builds navigation from the operator's current permissions. [Entrypoint](../../admin-web/src/main.tsx) · [Routes and navigation](../../admin-web/src/app/App.tsx) |
| API and session | The browser sends same-origin requests to the Admin transport. Supabase validates the account, cookie session and current grants. Sensitive routes also require their specified owner or recent verification proof. [API client](../../admin-web/src/api/client.ts) · [Transport](../../deploy/platform-admin/README.md) · [Security model](ADMIN_SECURITY_MODEL.md) |
| Data and recovery | Groups, Members, Transactions, Ledgers, Reconciliations and Request history use feature-specific routes. An uncertain operation keeps its original request key so its outcome can be checked before another write. [Feature implementations](../../admin-web/src/features) |
| BuriMunsi access | The BuriMunsi access route manages scoped operator approvals and device provisioning. The backend rechecks the shared principal and the permitted operation. Protected installation delivery requires qualification on the selected host and receiving device. [React feature](../../admin-web/src/features/burimunsi) · [Provisioning service](../../supabase/functions/_shared/domain/burimunsi/admin-provisioning.js) |
| Installation and updates | Production, qualification and fixture builds use the same React source. The service worker caches the versioned static shell. The release receipt pairs the artifact with its source and public configuration. [Build and verification](../../admin-web/README.md) |

## Verification

The Admin package documents the locked tests, compiled browser smoke check and artifact verification commands. [Build and verification](../../admin-web/README.md)

A fresh materialization of the local source candidate passed TypeScript checks, lint, 960 React tests, 118 transport tests and five compiled Chrome flows. Hosted role checks, installed-client upgrade and rollback, and protected BuriMunsi delivery remain open. [Source and custody receipt](../implementation/2026-11-20-react-admin-source-qualification.json) · [Implementation plan](../plans/2026-11-18-collect-cleanup-refactoring.md)

The 15 August architecture record is preserved at Git commit `34dcf6ee16b03b92d2131f34aa2ab9b3e73da3a4` under this same path. Its SHA-256 is `7775a518480eb5e35c864a0e57aec61ab64d8a93b525620046a89ae9603ad133`.
