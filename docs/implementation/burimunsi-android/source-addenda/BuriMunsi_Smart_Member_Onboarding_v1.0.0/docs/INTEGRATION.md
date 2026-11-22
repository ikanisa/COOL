# BuriMunsi — Smart onboarding extension, v1.0.0

**Target:** native Android Staff app and existing Collect/Cloudflare backend. **Integration stage:** standalone source module with tests, NOT merged into the active candidate; no live DB, APK or provider operation was modified.

## Existing project evidence / boundaries

Reviewed 13 November 2026 testing-readiness notes and 9 November A04 consolidated source README from the BuriMunsi Drive folder. Those notes identify native Staff Android, Collect PostgreSQL, Cloudflare Admin, controlled payer evidence and existing financial-session safety rules. They do **not** provide this module with the exact canonical table names, compiled app theme components or Android package layout. Therefore namespaced integration adapters are supplied rather than SQL that guesses financial table names. Reuse actual Compose theme and components during merge. Theme fallback uses current orange `#FF733E` and violet `#5144C9` inferred from BuriMunsi branding (not extracted native tokens).

## Functional flow

1. Existing Members `+` opens `SmartOnboardingScreen` with the current session-bound gateway.
2. **Suggested from MoMo** lists payer *candidate* keys from supported SMS-derived events **only when the receiving account scope is verified**. Aggregate by canonical payer key; exclude linked enrolled payer keys; do not derive a payer key from name or last 3 digits. Search server-side by normalized name or last 3 digits; cap results to 100. Show MoMo name / `···731` only. Do not disclose full numbers on the suggestion screen.
3. Tap candidate → prefill name, collect full number, check last 3 digits against evidence; staff must independently verify ownership/identity, terms and privacy consent. Member creation requires the existing authenticated authorization and transaction-bound unique normalized phone. *Do not automatically assign old payments to the new membership.*
4. **Add manually** uses the same verification and creation path.
5. **Import** accepts JPEG/PNG/WEBP directly, CSV directly; PDF up to 10 pages when server PDF converter is supplied, and XLSX through a host parser adapter. Images/PDF page images use the OpenAI Responses vision API to transcribe into strict JSON rows. Each parsed row is `ready`, `invalid` or `duplicate_in_file`. Staff corrects every row and explicitly verifies owner, terms and consent before adding it to the review batch, then submits one batch. Server still validates every row and reports created/duplicate/invalid/verification-needed outcomes. No automatic membership creation at OCR time.

## Backend API wiring

Mount `makeOnboardingHandlers()` under the existing authenticated Staff API gateway, not a new public service. Recommended route mapping (adapt to canonical server routing):

- `GET /api/staff/members/suggestions?search=...` → `suggestions`
- `POST /api/staff/members` → `enroll` (use `Idempotency-Key`)
- `POST /api/staff/members/import/preview` (multipart file, max 10 MB) → `parseImage` (handles all document types)
- `POST /api/staff/members/import/commit` → `commitImport` (batch `Idempotency-Key`)

Adapters required from the *actual* Collect source: `authorize(req)` returning {id,tenantId,canEnroll}; `repository.listPayerEvidence(tenantId)` and `repository.listMemberPayerBindings(tenantId)`; and a transaction-capable `store.transaction(tx => ...)` with `findRequest`, `findByPhone`, `findCandidate`, `createMember`, `audit`, `saveRequest`. All queries must be tenant/branch-scoped and apply real RBAC. Use trusted server-side key storage; set no public access to raw SMS bodies. In `listPayerEvidence`, return only supported events from verified receiving scope, with `kind:'MOMO_PAYER', classification:'SUPPORTED', payerKey, payerName, last3,receivedAt,scopeVerified:true`. Canonical records with no reliable payerKey must remain out of suggestions. Do not treat an SMS observation as payment confirmation.

**Database migration contract:** create/reuse an institution-scoped member number uniqueness constraint, a (tenant,idempotency-key) unique request journal, durable member identity/consent evidence and audit records. Keep member creation and idempotency journal in the same DB transaction; handle serialization/deadlock retries safely. Do not rename, mutate, or re-credit any existing financial ledgers. Actual DDL must be written against the checked live schema; this package intentionally does not invent canonical table names.

## OCR security and operational notes

Use OpenAI Responses API server-side only. `OPENAI_API_KEY` must stay in the backend. `store:false` is set and strict JSON schema is requested; this is not an assertion of zero retention. Check institution-specific data-protection permissions, hosting location, provider/processor arrangements, redaction policy, record retention, logging and any required overseas-storage authorisation **before** sending member lists to an external service. Do not send full unfiltered SMS bodies to OCR. Crop extraneous sensitive data before submission where possible. Avoid persisting unneeded raw upload bytes; apply short TTLs and access controls if stored. Refusals, malformed output, incomplete results, unreadable handwriting and uncertainty fail to the human review screen.

The source supports PNG/JPEG/WEBP and CSV immediately. For PDF, supply a trusted local page rasterizer (fitz/Poppler) with page limit; for XLSX, supply a pinned, reviewed parser in the actual backend. No arbitrary upload filename is passed to a shell. Enforce max per-request and per-tenant rate limits, file signature validation, antivirus scanning, field-length caps and approved permission to upload documents in the host server.

## Android wiring

Copy `SmartOnboardingScreen.kt` into the existing Android module under a matching package, adjust package/imports/Material icons per current Gradle, and replace the `+` action to navigate to this screen. Implement `OnboardingGateway` using the *existing* PIN/session-bound authenticated ApiClient; never create separate tokens, bypass Owner/Staff permissions or silently replay uncertain POST operations. Use `ActivityResultContracts.OpenDocument` for MIME types `image/jpeg`, `image/png`, `image/webp`, `application/pdf`, `text/csv`, `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`; read content from the returned content URI with a strict cap and close streams. Reuse the canonical network retry + operation journal; persist import batch idempotency keys across app recreation; refresh Memberships on successful creation.

The UI is intentionally self-contained. Integrators must apply existing localized design tokens, accessibility labels, strings and app navigation. Browser Admin screens can use the same backend endpoints but are not authored in this native extension.

## Required integration acceptance

- Baseline Android compile, Staff/receiving flavors, device tests and all original 8 routes unaffected.
- Confirm 0 suggestions for unrelated payer, unverified receiver, unsupported message, registered payer; verify mixed case/accent search and suffix collisions.
- Confirm two payers with identical names/last three digits are not merged; no full number or financial balance appears on suggestions.
- Verify device loss, logout, stale session, API timeout, duplicate taps and retry do not create two members.
- Confirm existing raw SMS, payment suspense, reconciliation and confirmed ledger remain unchanged on member creation.
- Verify OCR with real permitted handwriting, Kinyarwanda/French names, rotated scans and duplicate phone formats; no silent row import.
- Document lawful transfer/processor authorisation before sending any real member data to external OCR.

## Running local tests

`cd backend && npm test` (Node >=20, no external dependencies for tests). Tests exercise isolated domain behavior; they do not establish Android compilation, live Collect SQL compatibility, OCR service connectivity or deployment.
