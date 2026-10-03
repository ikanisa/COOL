# Independent operator email Auth source review

The corrected narrow helper has no additional actionable defect from this review.
The root owner's actual final run passed 31/31 tests, with seven source inputs
unchanged before and after. All seven retained owner-source files were compared
with current source during this review and matched. `verification.json` records
that dated association; `owner-final31/` preserves the actual log, receipt,
binding and seven source copies. Successful tests were not rerun by the reviewer.

The final helper SHA256 is
`a6edff976eee3f65ce9cbccdbe84dfc2f2c1e99f78d26b09f2f69a676dc0df05`.
The original inspected helper remains in `subject/` at SHA256
`645bd7f40400fe9dff8dbd78cd3aebebee60bba3b615a7e479a79d4263022e62`.
This leaf is separate from the sealed release follow-up and root-owned Auth packet.
No credential, Keychain, hosted Auth endpoint, OTP or sender was accessed by this
reviewer, and no product source was edited.

The root owner fixed these reported findings:

1. Original lines97–114 accepted complete SMTP metadata even when an enabled
   email hook was invalid. A synthetic invalid hook reached GET/PATCH/GET and
   `CONFIGURED_READBACK_VERIFIED`. The corrected helper validates the selected
   active hook independently; missing/null hook selection remains unknown.
   An enabled hook replaces SMTP according to the directly checked
   [Supabase Send Email Hook behavior table](https://supabase.com/docs/guides/auth/auth-hooks/send-email-hook).
2. Original lines117–123 accepted arbitrary selected-field values, and
   lines153/172 reflected them in saved evidence. A synthetic canary under a
   boolean key was reflected, while integer0/1 values were accepted as booleans.
   The corrected helper validates types before projection or mutation, rejects
   duplicate/nonfinite/oversized JSON values, and redacts unknown changed-key names.
3. The first revised HTTP worker inherited the parent's environment. The final
   child uses only the explicit `PATH`/`PYTHONUTF8` environment, with credentials
   and configuration passed through private pipes. The owner's actual local
   child test covers absence of inherited credential/canary environment values.
4. Python equality initially accepted unrelated `false`→`0`, `1`→`1.0` and
   equivalent nested type changes as unchanged. Final readback uses canonical,
   type-preserving JSON and checks field presence. A mismatch after PATCH stays
   uncertain, with no retry or automatic rollback.

The corrected private worker accepts only GET or the exact eight-field/type/value
PATCH derived from the current public code template. It cannot load credentials.
Each HTTP exchange now has a 20-second child-process deadline, including DNS and
response-body work, a two-megabyte body limit and redirect refusal. A timeout after
a mutation attempt remains uncertain. The patch excludes unrelated phone, SMTP,
hook, signup, redirect and MFA configuration.

`review_reproduction.py` and `original-reproduction.json` retain three actual
injected defect reproductions against the original subject. The corrected
`corrected_reproduction.py`/`corrected-reproduction.json` retain five passing
injected guard checks against the final helper. These checks are independent of
the owner's 31-test run. The original 19-test scope and owner predecessor 29/30
runs remain historical; counts are not added across revisions or scopes.

The inspected official [Supabase Management OpenAPI artifact](https://raw.githubusercontent.com/supabase/supabase/master/apps/docs/spec/api_v1_openapi.json)
defines SMTP port as string/null and selected boolean fields, including
`mailer_allow_unverified_email_sign_ins`, as boolean/null. The helper's canonical
port range is a conservative readiness policy, not a published wire restriction.
`management-wire-schema-check.json` preserves the precise GET/PATCH distinctions.
The selected parser intentionally does not validate the complete required GET
response schema. Missing nullable values remain unknown, and unknown phone/hook
state blocks mutation.

The legacy `supabase_apply_auth_hardening.sh` remains a broader deployment helper:
it has no curl connect/total deadline or independent Auth GET readback and updates
Edge secrets before the Auth PATCH. Its secret-argument protections were inspected;
the complete hosted multi-operation behavior was not exercised here. Use of that
helper does not establish narrow email acceptance.

Final coverage includes synthetic orchestration and real local child
timeout/environment isolation. SMTP/hook metadata does not prove delivery,
receipt of a code, verified owner identity or a current operator session. No real
Management API, email provider, OTP or hosted write was exercised by this review.
No production acceptance or source freeze is claimed. The historical
`copy_only_unreviewed_candidate` label in `subject-bindings.json` describes only
unapproved review copies and is not a release-candidate designation.
