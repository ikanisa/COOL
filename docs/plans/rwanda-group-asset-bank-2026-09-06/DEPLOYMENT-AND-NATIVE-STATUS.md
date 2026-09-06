# Group-photo deployment and Android follow-up

6 September 2026. **The database migrations are deployed and independently verified. Application distribution remains blocked by MOBILE-DESIGN-100.** All six scoped Android photo-journey checks pass in the disposable Collect emulator.

## Database result

The linked project was confirmed as COOL (`lhbowpbcpwoiparwnwgt`, PostgreSQL 17). The pending queue contained exactly the earlier owner-requested MoMo-code migration and the photo migration. Both SQL files were snapshotted, hashed and applied in sequence through the repository's existing governed Management API migration helper. No unrelated Edge Functions were deployed.

- `20260906093000_member_profile_momo_code` restores the optional private MoMo code through the member-profile API and retains the old five-argument RPC.
- `20260906160000_group_cover_bank_and_atomic_creation_media` adds atomic cover/colour persistence during attested creation and validates known cover versions.
- All **124 remote migration versions match** the local chain. All **four deployed function bodies match** the reviewed SQL. Collection RLS remains enabled. Helper and anonymous execute permissions remain denied.
- The actual REST endpoint rejected an anonymous photo-RPC call with **HTTP 401 / SQLSTATE 42501**, confirming the deployed endpoint's access boundary.
- No existing customer profile, group, contribution or payment row was rewritten by these migrations. Existing library-reference row count remained zero. This was a schema/function deployment, not an authenticated live payment or group-creation UAT.

The live-schema preflight found an enum mismatch hidden by the earlier lightweight fixture. `public_status` is `collection_visibility`, so the photo trigger now casts it to text before its null-safe comparison. The previous SQL failed in the corrected fixture with an invalid enum-input error; the fixed migration passes all **nine** cover/capability checks.

The previous MoMo-code PostgreSQL rollback test remains documented in the owner-annotation evidence. A new attempt could not reach the local Docker API and was cancelled; Docker and unrelated containers were not restarted. Six supplemental executable checks of the actual MoMo-code migration passed in isolated PostgreSQL, covering validation, atomicity, compatibility, privacy and grants. Their legacy dependency RPC is a fixture; this is not a replacement claim for fresh full-schema UAT.

Security advisors reported two additional warnings for the two new authenticated `SECURITY DEFINER` overloads. These are deliberate API wrappers around the existing gated functions: both enforce caller identity, use fixed search paths and explicit grants, and preserve the existing owner/geographic/device rules. No anonymous or direct-table access was added. The advisor inventory changed from 236 to 238 notices, with no ERROR-level finding. See the [Supabase advisor explanation](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).

Machine-readable evidence: [DEPLOYMENT-VERIFICATION.json](DEPLOYMENT-VERIFICATION.json). Migration handling was checked against the [current Supabase migration documentation](https://supabase.com/docs/guides/deployment/database-migrations) and changelog; no applicable breaking change was identified for this PostgreSQL function deployment.

## Native correction and checks

The Android review uses only `Collect_Design_Renderer_QA_20260905` / `emulator-5558` and the debug `app.cool.mobile.dev` fixture. No signed-in device data or production package is used. The test entry refuses non-debug, web and non-dev native builds. Android input events exercise the actual keyboard; Flutter text-entry emulation is disabled.

The first setup attempts exposed a system handwriting tutorial and a modal-focus race. The driver now focuses the settled field through Android accessibility bounds, temporarily disables the emulator handwriting prompt and restores the prior setting afterward. After the cold boot, Android displayed its own System UI ANR dialog; selecting Wait on the disposable AVD cleared that obstruction before the final passing run. The driver waits for each Android input character to reach the real field, and taps the visible intersection of the actual photo InkWell with its scroll viewport. Android can merge sparse rows into wider accessibility bounds. After heavy host contention interrupted repeated runs, only the disposable Collect AVD was restarted with host GPU rendering; unrelated devices and builds were left alone. These are fixture setup corrections, not application acceptance results.

The native landscape keyboard then exposed a real **38-pixel bottom overflow** in the photo sheet. When vertical space is short, the header and confirmation now scroll with the photo content; stable widget keys retain search focus through the layout change. Normal-height views retain their fixed header and confirmation. The search field uses a non-floating label so it cannot be clipped above the short viewport at 200% text while the keyboard is open. This is a keyboard adaptation of the selected neutral catalogue/sheet pattern; the source cohort remains LIVE-033 and the owner's `Cards.png` editorial cards.

All **136 affected Flutter tests pass**, including the added landscape keyboard cases at 100% and 200% text. Focused analysis reports no issues. The native matrix covers portrait/landscape at Android font scales 1 and 2, real `gusaba` entry, photo selection, explicit confirmation, saving the exact v2 reference, cancellation and image removal. All **six scoped native cases pass** on the fresh debug candidate, with no captured Flutter framework errors. The form is scrolled to expose Save in large-text landscape. Original orientation, font and handwriting settings were read back and restored. Earlier attempts stopped on a cold-boot Android System UI ANR or incomplete driver scrolling; they remain incomplete evidence and are superseded only for this scoped journey by the final passing run.

The installed package SHA-256 exactly matches the tested APK (`b9ca3de1a01596f7c22c26dce83a99c80fa74a6449cbf28332239ddce7b89f6e`). All **88 bundled cover/thumbnail hashes** match the runtime manifest; no original group-photo PNG is bundled. The 225,932,113-byte artifact is a universal debug fixture, not a production size or performance result. Seventeen Android captures record keyboard, selection, confirmation, saved cards and removal. The final 200% landscape keyboard and Save framing, portrait saved card and removal fallback were visually inspected.

See [NATIVE-VERIFICATION.json](NATIVE-VERIFICATION.json) for exact results, file hashes and local capture paths. The four scoped app/manifest inputs stayed unchanged through the build/run capture; the host driver was corrected after compilation. Full application source/build acceptance remains outside this result.

## Remaining release boundary

`make mobile-design-gate` remains **BLOCKED** by the existing acceptance, source/build binding, full route/state and open-finding requirements. This scoped photo work does not supply whole-app native acceptance, iOS device evidence, local cultural/language approval or production performance certification. Debug emulator frame/jank messages are not a performance benchmark. No acceptance score, required case, baseline or owner approval was changed.

The [interactive browser fixture](http://collect.localhost:4195/#/home) continues to use synthetic in-memory groups. Reloading resets those groups. Database readiness and the fixture demonstration are separate evidence layers; the production mobile build has not been distributed.
