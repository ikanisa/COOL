# Native operator provisioning — source implementation

This adds owner-controlled native credentials to the **existing Collect Admin,
managed identities, database and application fence**. It creates no Supabase Auth
user, signup route, wallet, financial ledger, receiving/SIM binding or provider
dispatch. The existing owner approval is a prerequisite, not something a PIN can
replace. A scope may be prepared while native operations remain disabled; this
flow never enables it.

`proposal.sql` is a proposal, **not an applied migration**. The deployment owner
must generate the migration name with the installed Supabase CLI, review its
source and grants, qualify on the native PostgreSQL clone, and update the normal
reviewed migration/lock artifacts. Do not apply the proposal as an ad-hoc runtime
SQL command. No seed or runtime provisioning is included.
The proposal enforces one native account per shared principal/group without
deduplication, and prevents changing an existing native account's principal,
group, UUID or creation time. Existing duplicate identities stop installation.

## Server contract

Every route below requires the genuine existing owner BFF cookie, its configured
Admin Origin, existing current managed admission and fresh independent sensitive
email proof. POST also requires existing CSRF/requested-with protection. The
server selects `BURIMUNSI_COLLECTION_ID`; the body collection is only a concurrency
assertion. Every private helper rechecks the actual owner/cookie/email tuple in
the same Collect transaction/lock as its work. Missing schema/configuration denies.

Base: `/api/admin/burimunsi/provisioning` (through existing `admin-api`).

| Action | Contract |
|---|---|
| `GET` base | Current scope version/enabled state, owner-approved native account versions, installation metadata. No PIN hash, token hash, ciphertext or token. |
| `POST` base, `operation:set_pin` | UUID request ID, exact collection/scope/principal/approval/account versions, nonsecret reason and transient four-digit `pin`. Initial account version is zero. Phone/role/capability ceiling come from the current approved shared account. |
| `POST` base, `operation:grant_installation` | Same common assertions plus existing `accountId`, exact `installationId`, `profile`, `grantId` (null only for first grant) and `expectedGrantVersion` (zero only for first grant). Token is generated server-side. |
| `POST` base, `operation:revoke_installation` | Same exact existing grant tuple/versions. Revocation can reduce authority even when its target approval is no longer active. |
| `GET /requests/:UUID` | Original actor/session-bound outcome. Never redispatches. Returns `{contractVersion:1,collectionId,requestId,found,receipt?}`. |
| `POST /requests/:UUID/cancel` | Body `{collectionId}`. Under the same writer lock, returns the original committed receipt or retains a cancellation tombstone. A late original request cannot provision after this tombstone. |
| `POST /requests/:UUID/delivery` | Body `{collectionId,installationId,profile,grantVersion}`. Explicit, fresh-owner-only readback of a still-current grant's encrypted delivery. Exact original actor/session plus current account/approval/scope/grant versions required. No refresh token or BFF cookie is exported. |

Common mutation fields are exactly `requestId`, `collectionId`, `scopeVersion`,
`principalId`, `approvalVersion`, `expectedAccountVersion`, `reason`, `operation`.
`set_pin` adds only `pin`; grant/revoke add only the five installation fields
above. Successful mutation receipts contain the exact operation and versions;
grant receipts additionally identify the installation/grant and delivery expiry.
**Mutation responses and ordinary outcome lookup never contain a device token.**

PIN reset revokes all that account's native sessions. Grant rotation/revocation
revokes the affected grant's native sessions. Existing managed sign-in identity,
canonical gateway credentials, upload holds, captured evidence, processing
checkpoints and financial/canonical journals are not changed. Rotation preserves
the installation/profile/custodian tuple; it cannot quietly transfer a device to
another person. Multi-account legacy grants require explicit separate review.

## Secret custody

Use the root-approved protected settings, never public native build fields:

* `BURIMUNSI_PIN_PEPPER_BASE64`: canonical base64, 32–256 random bytes; an
  independently generated protected pepper. No default or client substitute.
* `BURIMUNSI_PIN_PEPPER_ID`: stable nonsecret key identifier. The current policy
  does not verify hashes from another pepper ID: changing it is a controlled
  credential-reset operation, not a silent key rotation.
* Existing `DATA_KEY_ID`, `DATA_ENCRYPTION_KEY` and, when applicable,
  `DATA_DECRYPTION_KEYS_JSON` for shared AES-GCM custody. Existing BFF `SESSION_*`
  settings remain independent. Provisioning introduces no competing encryption
  system or cursor key. `BURIMUNSI_CURSOR_KEY_BASE64` remains the root runtime
  factory's separate concern.

`PinHasher` uses its existing HMAC prehash + PBKDF2-SHA256 policy at 600,000
iterations with random 16-byte salt. The original command fingerprint is a
pepper-keyed HMAC, including the original PIN, rather than an offline-testable
plain PIN digest. SQL receives only the protected record/fingerprint. PINs are
not retained in delivery custody, receipts, audit details or pending intent.

Installation tokens are 32 cryptographically random bytes encoded as 64 lowercase
hex characters. The active grant stores only SHA256(token). Recovery custody is
AES-GCM sealed with AAD binding deployment profile, original owner/session,
collection/request, custodian account, grant, installation/profile and versions.
Server readback expires 15 minutes after the command or as soon as any bound
account/approval/scope/grant version changes. The immutable historical ciphertext
is not physically erased at expiry; key custody/backup/retention remain governed
operations, and expired ciphertext is never released by this route.

The Admin pending-attempt journal contains only the exact nonsecret intent.
It never contains a PIN, token or ciphertext, and restored work never dispatches
automatically. A confirmed grant checkpoint stays until the owner closes delivery
so a reload can recover the same receipt and still-current token. A lost PIN
request can be checked/cancelled without retaining or re-entering its PIN.
The protected viewer masks by default, redacts its value object's diagnostics,
and closes on background, expiry or an observed authority-fence change. Closing
delivery is a local workflow acknowledgement, **not MDM-installation proof**.

## Remaining qualification and runtime gates

1. Adopt and qualify the proposed SQL using actual PostgreSQL roles, RLS,
   managed Auth/current-email state, application fence and current platform
   schema. Required cases: initial account, reset/revoked sessions, stale/disabled
   approvals and capability ceilings, wrong owner/Origin/session/source/scope,
   initial grant/rotation/revocation, receiver uniqueness, custody isolation,
   outcome/cancel/late-commit races, token expiry and no capture/financial changes.
2. Install the real reviewed schema and protected secrets through the existing
   admitted deployment, and commission the real approved group/receiving scope.
   Missing scope is an explicit failure, never a synthetic group/wallet.
3. Establish the existing confirmed owner/team identities and current independent
   email proof through the genuine shared sign-in flow. These source tests do not
   create real users, send messages or provide fresh-email evidence.
4. Use the native app's public **Installation ID** and exact build profile:
   `staff` or `internal_receiver`. Deliver via approved device management using
   restriction keys **`burimunsi_installation_id`** and
   **`burimunsi_installation_token`**. The supplied UUID must equal the persisted
   local installation ID; reinstallation/replacement requires an explicit new
   grant. Real MDM custody/delivery and installed sign-in remain unverified here.
5. Complete T002 wallet/SIM/custodian evidence and canonical gateway pairing
   separately. A native app grant does not configure receiving subscriptions,
   remove upload holds or authorise any real SMS/payment/provider action.

The new Node tests use production crypto and the actual Admin/BFF route over a
reduced SQLite fixture; PostgreSQL procedures/roles are explicit substitutes.
Flutter tests use synthetic local accounts and cover pending-intent/lost-response
recovery plus responsive controls. These are source/local proofs only, not a
database migration, hosted deployment, physical-device or production acceptance.
