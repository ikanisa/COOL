# Owner annotation corrections — 6 September 2026

Local implementation and scoped verification passed. `MOBILE-DESIGN-100` remains blocked; this is not production approval or a claim of complete design fidelity.

## Implemented behavior

- Create-group inputs use 16dp rounded corners and 16dp horizontal / 12dp vertical padding. Labels and icons align with enlarged text and multiline content. The form scrolls with the real keyboard; the full Continue action remains reachable.
- Home’s former scan-to-join prompts and quick action now read **Explore Groups** and open `/groups?filter=featured`, restricted to the active public selection. Private invitation QR capability remains available in its existing flow.
- **Featured Groups** remains on Home during loading, empty membership, failure and offline states, with truthful loading/empty content.
- Profile switches between **MoMo number** and optional **MoMo code**, retaining both drafts and saving both values. Number-only profiles remain valid. Codes preserve leading zeros and accept 4–9 digits. Geographic profile rules and private-account access remain enforced.
- Contribution entry and review show the beneficiary name and number without a redundant network prefix. Synthetic `QA MoMo receiver` is now `QA MoMo`; actual beneficiary names and payment routing are unchanged.

## Evidence

The final full run passed **192 widget tests**, covering Home discovery and states, profile validation/save/draft switching, payment behavior, native bank contribution, offline cache, accessibility geometry and responsive layouts. Initial test-only timing/scroll failures were corrected and the entire affected suite rerun successfully. The final JSON test report is authoritative.

The rebuilt Android development fixture passed **36 native input cases**, with **68 actual OS screenshots**, across portrait/landscape and 100%/200% OS text size. This includes the new MoMo-code tab. Source and harness hashes matched before and after the final run. The installed APK hash matched the retained QA artifact. All 68 images decoded and passed the green-focus-frame raster check. No `E/flutter` or `FATAL EXCEPTION` was found in the final run log.

Representative native and widget images were visually inspected; this does not certify every state against its original reference. The browser’s latest annotation page loaded all 13 displayed images and reported no warnings or errors. The rebuilt gallery distinguishes current tests/captures from retained historical evidence.

The private MoMo-code migration passed transaction-only tests on the local fixture database, including save/reload, leading zeros, invalid-write atomicity, clearing, legacy RPC compatibility, diaspora handling, account isolation and permissions. All database test changes were rolled back. **The backend migration has not been deployed.** Live MoMo-code persistence depends on that release.

The disposable Collect QA emulator’s original settings were restored and the emulator stopped. No physical phone or other task’s emulator was changed; no payment or form action was submitted in the native matrix. No baseline was regenerated and no production artifact was distributed.

## Review and provenance

- [Latest Home and form review](http://collect.localhost:4191/responsive.html?v=20260906-owner-updates)
- [Complete native keyboard matrix](http://collect.localhost:4191/native-keyboard.html)
- [Machine-readable verification](owner-annotations-verification-2026-09-06.json)
- Evidence: `.cache/revolut-design-20260906/owner-annotations/`
- Authoritative native run: `native-final/`; earlier interrupted recipient/code-tab runs are superseded.
- The root acceptance status, required cases, annotations and open findings are retained unchanged. Full reference/state review, native screen-reader evidence, current iOS keyboard evidence and exact production artifact acceptance remain open.
