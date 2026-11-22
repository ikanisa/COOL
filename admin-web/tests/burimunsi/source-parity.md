# BuriMunsi Admin read contract parity

The fixture generator pins migrations, routes and adapters from the current Cloud source by SHA-256. On a disposable, socket-only PostgreSQL cluster it checks response contracts against synthetic records.

The generator extracts the three actual PostgreSQL directory functions, runs them on a disposable local socket-only cluster with synthetic rows, and exercises the Cloud setup and provisioning response validators. It stubs application/owner admission, supporting tables, gateway state and the native approval-current function, so the fixture validates output shape and adapter compatibility only. It is not an RLS, authorization, device, carrier, or production integration test. The committed JSON is synthetic test input and is never used as application data.

From `admin-web`, verify the source fixture and run the affected suite:

```sh
node tests/burimunsi/source-parity.postgres.mjs
npm test -- tests/burimunsi
npm run typecheck
npm run lint
```

`BURI_TEST_SOURCE_ROOT`, `BURI_TEST_PG_BIN`, and `BURI_TEST_PG_MODULE` override the checkout root, local PostgreSQL binary directory, and local `pg` module. Source hashes must match. The generator makes its own temporary cluster under `/private/tmp` and stops and removes it. `--write` intentionally refreshes the synthetic JSON after an authorized fixture change. No network listener, production data, or live write is used.

Observed source contracts and boundaries:

- An unfiltered `momo/native-setup` directory returns active collection records, all scope records, accounts, and an empty installation list. Its setup adapter permits empty or long collection titles, and normal group text validation permits tabs/newlines. The React label now normalizes controls, falls back to the exact group ID when the label is empty, and appends the exact group ID when truncating. The unmodified ID and scope version remain the selection and concurrency references.
- Operator directory IDs are PostgreSQL text. Its GET route can return an existing opaque Admin ID or principal ID; the React read directory retains them exactly without loosening the native provisioning UUID parser. The operator preparation component is preview-only and cannot send approval changes. Retained approval request recovery and the backend approval POST still independently require UUID identifiers.
- The provisioning adapter independently requires UUID principal IDs. In the synthetic case of an approved opaque principal, it raises an `invalid_parameter` `ApiError` (status 400), even though the operators directory can return that ID. Fixing that difference requires a separately qualified backend contract change; this parser cannot make the provisioning request succeed.
- If a historical approval and current team row share an Admin ID but have different principal IDs, the current page cannot safely merge the two identities. React continues to reject the whole operator directory. The fixture demonstrates the SQL shape using a simplified relink; it does not establish that a particular production transition or record exists. Source permits multiple approvals by Admin ID because the unique approval keys are collection/principal and collection/phone, while the React parser currently rejects ambiguous duplicate Admin IDs. Supporting such history requires an explicit display and workflow decision.
- The setup `enabled`/`paired` fields are recorded scope metadata. A false value is not, by itself, proof that the existing Android SMS-to-ledger Sync path is unavailable. Recorded grants similarly do not prove physical device possession or carrier delivery.
- Route-source review shows current-owner and fresh-email requirements, deployment origin/application-work checks, and server-side owner checks. The component tests verify its owner/permission and read-only UI behavior with synthetic sessions. Neither evidence proves live authentication, row-level policy, database privileges, or production route behavior.

The React parser intentionally retains conservative input limits and rejects malformed/ambiguous records. The backend can theoretically return other unusually long or control-containing operator fields permitted by text storage; those edge cases remain fail-closed until a source-supported, identity-safe presentation is qualified. This work does not enable a write flag or deploy a release.
