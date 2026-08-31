# Collect Admin panel UAT and QA status

Date: 2026-08-31

## Verdict

The code-owned and hosted Collect Admin release gates pass. The panel is not yet eligible for an unconditional production-readiness **GO** because the remaining gates require independent human operators, additional real or approved staging records, physical devices and non-Chromium browsers, and accountable operational risk acceptance. The current release verdict is therefore **CONDITIONAL NO-GO**.

## Completed evidence

| Gate | Status | Evidence |
| --- | --- | --- |
| Exact release source | Pass | Commit `84c7858a66e951a43648a16f2531545611eb086c` was isolated from unrelated in-progress payment-rail work. Static analysis passed and all 288 Flutter tests passed. |
| Supabase migration | Pass | Migration `20260831084239_expand_admin_queue_sla_support` is recorded in hosted migration history. Isolated parity is 83 local / 83 remote with no missing or extra applied migration. |
| Hosted database contract | Pass | Project is `ACTIVE_HEALTHY`; public schema is 392 expected / 392 remote; all 74 public tables have RLS; error-level security and performance advisor gates are clean. |
| Database security and workflow UAT | Pass, rollback scope | Linked rollback UAT passed for the complete role/permission matrix, non-admin denial, raw-evidence reveal, role management, feature flags, moderation, notification retry, payment reparse, independent maker/checker behavior, statement confirmation, reconciliation, balanced journal posting, exact-once behavior, and audit records. All synthetic state was rolled back. |
| Live WhatsApp authentication | Pass for positive path | A real production WhatsApp OTP was delivered and verified in the Codex web view. Authenticated routing and session persistence across reload passed. No OTP or session credential is retained in release evidence. |
| Live Admin routes | Pass for available data | Before deployment, all 33 routes rendered under a real authenticated session. Four detail routes used real live rows. Nine operational detail queues had no live rows and returned clean not-found/empty behavior instead of representative workflow evidence. |
| Hosted SLA defect remediation | Pass | Live UAT found `admin_get_queue_sla` rejecting current bank queues. The hosted function and client compatibility fallback were corrected. All nine bank queues now return the SLA RPC with HTTP 200 and zero HTTP failures, browser exceptions, or console errors. |
| Admin deployment | Pass | Cloudflare version `f3b75543-a8cb-4257-98a2-a7b417021a59` serves 100% of `collect-admin`; version `06657def-fd8a-4766-8db8-9b24f0464c2a` is retained for rollback. The custom-domain header/asset gate and the production PWA runtime/cache probe pass. |
| Post-deploy authenticated regression | Pass | All 19 workspace routes rendered in the Codex web view with zero console errors or warnings. Accessibility semantics exposed the navigation and workspace controls; 12 native Tab transitions produced visible semantic focus targets. A live 320 px compact check reported 320 px document width with no horizontal overflow. Cached reload completed in about 80 ms with no failed resources. |
| Automated visual coverage | Pass | The deterministic Admin matrix covers 33 routes at compact, tablet and desktop viewports: 99 screenshots, zero failures and zero false checks. |

## Remaining production-signoff gates

1. Run OTP resend, expiry, invalid-code, logout and fresh-login cycles without reusing or recording OTPs. Each new real-message send requires action-time authorization.
2. Use at least two separately authorized human operator accounts to complete live maker/checker and human role-matrix acceptance. The transactional synthetic actors prove backend enforcement but are not two-person operational acceptance.
3. Provide approved staging records, or explicitly authorize controlled production records, for end-to-end UI acceptance of statement import/reconciliation, notification retry, raw-evidence reveal, group moderation, feature flags and role management. The current live queues do not contain representative rows for every workflow.
4. Complete Safari and Firefox acceptance, physical iOS/Android PWA checks, VoiceOver/TalkBack traversal, real-device 200% zoom/reflow, interruption/recovery and assistive-technology signoff. Chromium automation and Flutter 200% text-scale tests do not replace those checks.
5. Record accountable owner approval for the operational runbook and the current Supabase platform risks: Free plan capacity, point-in-time recovery disabled, and Auth CAPTCHA disabled. Leaked-password protection is unavailable/relevant only if password authentication is enabled; the Admin positive path is phone OTP.

## Release boundary

The hosted build, database migration, RLS/RPC controls, rollback workflows, authenticated route rendering, PWA behavior and deployment rollback are production-ready. An unconditional **GO** must not be recorded until the five human/external gates above are evidenced or explicitly accepted by the named release owner.
