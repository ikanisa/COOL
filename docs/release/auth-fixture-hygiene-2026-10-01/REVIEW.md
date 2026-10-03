# Auth fixture hygiene review

The strict repository token scan remains unchanged. It found copied signed
session literals and structurally valid illustrative JWT literals in upstream
GoTrue test files; this review does not classify them as live credentials.

The plain JSON parser fixture now uses opaque synthetic access/refresh tokens.
Expired recovery fixtures are constructed through the existing unsigned helper.
Claims/expiry/asymmetric rejection fixtures keep their original header and claim
values and construct an explicitly invalid synthetic signature at runtime.
Production Auth/verification implementation and the upstream provenance hash
record are unchanged. No valid signature is made acceptable by this change.

The app's actual GoTrue public decoder and expiry validator are exercised by
`test/core/auth_fixture_token_test.dart`. The asymmetric case fetches an empty
JWKS through an in-memory HTTP adapter, rejects the dummy signature with an Auth
exception and leaves the session absent. Three cases passed in the original
root214 run before its analyzer caught a prohibited internal-member assertion;
root216 uses only the public SDK API and verifies the complete affected files.

The upstream integration suite requires separately resolved dotenv/test dev
dependencies and a local Auth stack. Its direct execution from the app's package
failed dependency resolution; that result remains retained in root213. The
three app-level cases do not claim the entire upstream integration suite ran.
Source binding records the changed fixture bytes without publishing tokens.
