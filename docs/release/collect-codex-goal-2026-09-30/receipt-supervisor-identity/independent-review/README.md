# Independent supervisor request-validation review

Three concrete boundary defects were reproduced against the retained draft handler and their repairs verified against the retained selected handler. The tests use a generated ephemeral synthetic P-256 key, native WebCrypto, the actual handler, and in-memory RPC stubs. They make no network or database call, retain no private key, and do not create a Keychain key or provision any identity.

The malformed JSON string escape formerly produced 503 `SUPERVISOR_AUTH_UNAVAILABLE`; it now produces 400 `SUPERVISOR_REQUEST_INVALID` without an RPC. An 8,193-byte body formerly exposed the unrelated `GATEWAY_BODY_TOO_LARGE` code; it now produces 413 `SUPERVISOR_BODY_TOO_LARGE` without an RPC. An uppercase request UUID formerly reached the observe stub and rejected its PostgreSQL-shaped lowercase reply as 502 `SUPERVISOR_OUTCOME_UNKNOWN`; canonical lowercase admission now refuses it before observe with 400 `SUPERVISOR_REQUEST_INVALID`.

`before-output.jsonl` and `after-output.jsonl` are actual new executions of the retained repro files. Each differs from the original repro only in its handler import path. `provenance.json` distinguishes the retained draft-before SHA from the separately inspected historical selected SHA; the latter was not retained byte for byte. The after capture has SHA 1649f602ae5c58ea22576a2328bca5104b88234d80b4e741386171e2813ea9aa. These are three local regression checks, not the broader root-owned signature or SQL suite.

Read-only review also covered the SQL current identity/expiry/revocation guards, bidirectional key reservation fence, exact request replay, actor-bound manual reconciliation, client fixed endpoint/audience, one fetch attempt, redacted result validation and separate Secure Enclave key tag. No additional concrete defect was found. This review is not production security acceptance, deployment evidence, genuine device attestation, Auth/provider-runtime validation or dispatch authority.

The retained file manifest excludes itself. No prior packet was modified.
