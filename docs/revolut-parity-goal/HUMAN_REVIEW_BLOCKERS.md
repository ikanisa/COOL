# Human Review and External Blockers

## Current

1. Store signing, TestFlight/App Store upload, Google Play upload, and public
   deployment are not authorized by the current goal.
2. Production Supabase changes and live payment execution are not authorized.
3. Additional user-assisted phone scrolling may be required for lower
   Payments, Profile, Security, authentication, and transfer-state references.
4. The iOS release owner must enable Associated Domains for the controlled
   `app.cool.mobile` App ID and provide/select a compatible provisioning
   profile before a signed distribution archive can pass.
5. The complete local Admin PWA release wrapper and artifact manifest pass with
   the public `COLLECT_ADMIN_WHATSAPP_PHONE=250795588248` value. Deployment is
   not authorized, and the current live host still serves stale icon/service-
   worker output, so live-host refresh and post-deploy verification remain
   external.
6. Play Developer Reporting needs authorized OAuth/gcloud access, and the
   remaining Play Console surfaces require an account owner to inspect them.
7. Android signing review and release-owner approval must be freshly recorded
   for version `1.2.2+10`; existing approvals are tied to `1.2.2+9` and are now
   rejected by both the approval evidence gate and aggregate release status.
8. E-075 reaches the exact paired physical iPhone 12 Pro, verifies Developer
   Mode and the staging signing/install/launch/attach path, rejects locked state
   fail closed, and passes the unlocked Dark matrix at 35/35 routes. The device
   owner must keep the phone available for the remaining actual VoiceOver,
   lifecycle, and permission checks; the route pass does not replace them.
9. E-077 verifies current-source exact-Simulator Camera denied/granted TCC
   states and visually reviewed recovery controls, and fixes automatic scanner
   recovery after Camera is enabled in App Settings. This does not replace the
   device owner's physical Camera Settings or VoiceOver run.
10. The physical lifecycle/Camera harnesses now prebuild before a bounded
    unlock window and reject missing markers, but the observed wireless phone
    auto-locked before lifecycle execution. Keep the exact phone unlocked—USB
    preferred—until lifecycle, Camera Settings recovery, and VoiceOver evidence
    is accepted.
11. E-078 supplies current Collect captures for 16 material states and records
    direct, pattern-only, and no-direct-analogue dispositions. Product Design
    must still provide the missing direct Auth/OTP and amount/review references
    or formally accept the bounded gaps; local screenshots cannot grant that
    approval.
12. E-079 revalidates the remaining boundary. The physical iPhone is currently
    offline; controlled ADB input is rejected as continuous human TalkBack
    traversal; and official Flutter guidance requires 3.47+ while the checked
    stable release list ends at 3.44. Physical accessibility/device work,
    governed built-in-Kotlin validation, and every accountable external action
    remain pending their required state or authority.

## Closure rule

These items do not block local implementation and testing. They block only the
corresponding external release or reference-dependent conclusion. No external
action will be inferred from local engineering readiness.
