# Edge public-error leakage audit

**Reviewed:** 28 September 2026. **Scope:** all eight current Supabase Edge HTTP entry points in supabase/functions, their error-response helpers, and directly related provider logging paths. This is a current-source and isolated HTTP-handler audit. The checkout is uncommitted, and deployed function versions and live logs were not accessible. Production S07 remains open.

## Confirmed source findings and changes

| Finding | Previous reachable response | Source correction | Focused proof |
| --- | --- | --- | --- |
| S07-01: internal authorization exception text in notification HTTP responses | _shared/cors.ts returned the exact developer exception text for missing internal signatures. send-notification, dispatch-notifications and collect-notification-operator used it in public error JSON. | _shared/cors.ts now emits authentication_required for recognized authentication failures and service_unavailable for other exceptions. authErrorStatus still independently preserves 401. | Mocked send and dispatch HTTP calls without the internal signature return 401 with only authentication_required. Injected SQL/provider text returns only service_unavailable; operator SQL failure is also suppressed. |
| S07-02: Play Integrity configuration diagnostics | verify-play-integrity returned a service-account-specific blocker when a required environment value was missing and exposed integrity_policy_unconfigured for an invalid private policy. | verify-play-integrity now returns play_integrity_unavailable for both configuration cases while preserving 503 and the existing fixed public rejection codes for user/verdict failures. Missing user auth returns authentication_required with 401. | Mocked authenticated HTTP calls with missing and invalid configuration return exactly play_integrity_unavailable; no configuration key, blocker or provider body is returned. |
| S07-03: internal ACL name on operator denial | collect-notification-operator returned the required notifications.read or notifications.manage permission identifier in a 403 response. | The denial now returns a fixed forbidden code with the same 403 status. | Mocked signed-in operator without the required permission receives exactly forbidden and no ACL name. |
| S07-04: sanitized operator input lost its client-error status | After the earlier shared sanitizer replaced raw messages, collect-notification-operator tried to recognize validation errors by regex on the sanitized text. Invalid input therefore reached a generic 409, indistinguishable from internal errors. | The command parser now marks only request-validation failures with OperatorInputError. The HTTP boundary maps that class to invalid_request/400 and unknown internal errors to service_unavailable/503. The trusted operator-ID failure remains an internal error. | Invalid action and bad limit return a fixed 400, injected Admin SQL failure returns fixed 503, and an authorized health call still returns its result. |

These changes preserve the internal authorization decision and fail-closed configuration behavior. They alter public error codes and restore distinct client/server status classes; no credential, SQL, provider, payment or success flow was changed.

## Entrypoint review

| Entrypoint | Current public-error path | Result of source review |
| --- | --- | --- |
| auth-send-whatsapp-otp | publicFailure maps developer-authored PublicError codes and unknown exceptions to a generic code. | No raw provider response was found in HTTP errors. Existing mock HTTP test injects a provider body and confirms it is absent. |
| ingest-payment-sms | publicFailure maps failed auth, RPC and parser dispatch errors to fixed codes. | No raw SQL/parser body was found in HTTP errors. The durable receipt response is a success payload, not a settlement claim. |
| parse-payment-sms | publicFailure maps parse and lease errors to fixed codes. | No raw SQL exception return or log was found in the inspected catch. This file was inspected but not edited because financial work owned it. Its cleanup-on-error branch still needs deployed failure testing. |
| verify-play-integrity | Fixed PublicError codes plus generic unknown-error response; configuration diagnostics normalized by this change. | No raw Google response body was found in HTTP errors. Auth and both configuration cases have focused handler tests. |
| prepare-roster-import | publicFailure suppresses SDK, SQL and model exception messages. | No raw OpenAI response body was found in HTTP errors; explicit validation and permission responses are developer-authored. Live model responses and logs were not available. |
| send-notification | safeErrorMessage catches internal auth and enqueue RPC failures. | Previously returned an internal auth exception; now returns stable codes. Injected SQL/provider text did not appear in HTTP JSON. |
| dispatch-notifications | safeErrorMessage catches authorization, claim and delivery failures; delivery log uses the same sanitizer. | Previously returned an internal auth exception; now returns stable codes. Injected claim error text did not appear in HTTP JSON. Actual provider telemetry was not accessible. |
| collect-notification-operator | The command parser marks request-validation errors; the HTTP boundary returns invalid_request/400, forbidden/403, authentication_required/401 or service_unavailable/503. | Internal auth and ACL names are no longer returned. Injected Admin RPC text did not appear in HTTP JSON. Valid authorized health response remains intact. |

## Verification

- python3 scripts/hardening/run_edge_http_tests.py: **36 passed, zero failed**, using actual handler source with isolated Supabase/provider adapters. The local TypeScript compiler executable was unavailable, so this command used its Bun execution fallback; it did not claim a type-check.
- deno check supabase/functions/*/index.ts: **passed for all eight entry points** using the real imports.
- deno test supabase/functions/_shared/notification_operator_test.ts: **five passed**.
- python3 scripts/hardening/source_integration_test.py: **16 passed**.
- git diff --check on changed TypeScript source and Python syntax check of the HTTP runner: **passed**.

The new HTTP cases cover error content and legitimate status behavior. They do not prove that the deployed functions match this checkout, that gateway-generated errors are sanitized, or that production logs and operator exports contain no sensitive payloads. A release owner must read back deployed function hashes and test a redacted error corpus on the authorized environment before closing S07.
