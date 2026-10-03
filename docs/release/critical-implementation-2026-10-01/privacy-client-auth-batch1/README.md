# BE05 client fresh-auth discovery

Read-only lookup, 2 October 2026. No client source or startup code changed; no OTP or Auth provider was called.

The live deletion consumer is `CollectRepository.requestAccountDeletion` (line 729), called by `account_legal_screens.dart` (line 296). It uses the legacy RPC as `<void>`, discards the UUID, and displays generic retry text for server/session/conflict errors. The screen has a local submitted flag, but no pending receipt, own-status lookup, stable typed request UUID or fresh-auth control.

The existing member OTP path is `AuthOtpGateway` -> `AuthScreen` -> profile hydration in `CollectRepository.signInWithOtp`. The repository method alone does not verify an OTP. A logged-in profile redirects `/auth` immediately, so simply navigating to `/auth` cannot display step-up verification. The generic OTP sender does not explicitly disable creation; a privacy-specific existing-subject sign-in must.

Recommended ownership is a dedicated member request transport/model/controller and verification surface, reusing OTP/CAPTCHA UI and existing identity-fence patterns. Keep an exact subject-bound submission UUID and normalized payload through response loss; use the new own-status RPC before retry, classify the server's fixed errors, and require explicit submission confirmation after verification. Fence Auth subject and session/generation before and after every await; use trusted Auth identity, not editable profile phone fields. SQL remains the authority for fresh `auth.sessions.created_at`; a refreshed JWT or local timestamp cannot prove freshness.

Admin MFA step-up supplies useful response/adoption fencing, disposal handling and no-secret error patterns. Its AAL2/same-SID flow does not establish a new member session, and platform approval/roster roles cannot be reused as member authority. Admin login's `shouldCreateUser:false` is a relevant existing-identity pattern.

A smaller alternative is explicit logout followed by normal OTP login with a guarded return target and a minimal subject-bound pending intent. That requires review of sign-out/profile disposal, clearing on account switch, correct fresh SID behavior and no automatic resubmission. Reusing the generic login route without logout or a dedicated step-up mode fails the current router condition.

Future verification should cover older live SID errors, actual new sign-in, cancel/provider failure, CAPTCHA recovery, switched-account and late-response fencing, exact request replay/response loss, conflict, own-only status and pending-review language. No hosted OTP, new-session issuance, Auth SDK adoption-race or device acceptance was executed here. Full BE05 and legal/retention/erasure scope remain open.

Exact source hashes, seven findings and the two implementation ownership options are recorded in `discovery.json`; twelve source files are captured for readback.
