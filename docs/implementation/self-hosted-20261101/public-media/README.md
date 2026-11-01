# Current-source public interface previews

These seven images were captured from the actual Flutter fixture entrypoint on 2026-11-01 and installed into the repository's public preview asset directory through the existing strict publisher. No hosted website was deployed.

The capture used Flutter 3.44.4 and Chrome for Testing 156.0.8078.80 at a 390 × 844 viewport and device scale 3, producing 1170 × 2532 PNGs. The official Chrome archive SHA-256 was `b711c720f774be355197f32edf37e0651418ba036d92446ee2da19ac017540a7`. The capture report independently records the executed browser binary hash, toolchain, compiler command, artifact inventory and verified served bytes.

The current fixture source fingerprint is `18be7b92dd1135a5f3c94d4fb5d8dba6cfd38635724ff863526a1f4e478cd2ab`. Sources and generated package bindings remained unchanged throughout capture. The recorded build inventory hash is `4b66a517afdb64eee379ff257d633a62b0a7f83e193c75ecd13ac2fb56b3fdc2`.

## Review scope

Each original PNG was inspected for correct route and visible content, text legibility, unintended clipping and overlap, and suitability as a synthetic interface preview. The independent review binds each image hash and the exact capture report. The long lists and legal pages continue below the viewport; these previews do not represent a complete interaction or legal-document review. The account-deletion route accurately shows that the backend-free fixture cannot check or submit a request.

| Preview | Actual route |
| --- | --- |
| Home | `/home` |
| Groups | `/groups` |
| Private group | `/groups/qa-private-group` |
| Security | `/settings/security` |
| Privacy Policy | `/settings/legal/privacy` |
| Terms and Conditions | `/settings/legal/terms` |
| Delete request, unavailable service state | `/settings/account/delete` |

The report records zero browser/diagnostic errors, zero unexpected external requests, and zero provider, hosted-service or database calls. The capture interceptor blocked remote resources before HTTP. The recorded Flutter engine fallback-font attempts were blocked and supplied no substitute bytes.

## Explicit acceptance limits

`visual-review.json` approves only the accuracy and quality of these actual captured previews. It sets design, native-device and release acceptance to false. The required `revolut-design@jean-bosco-skills` authority was unavailable; no substitute design system or visual comparator was used. Provider delivery, real account-deletion handling, physical-device behavior, complete responsive/accessibility coverage and production deployment remain separate acceptance work.

## Preserved evidence

`capture-report.json`, `visual-review.json` and `publication.json` bind this run. `replacement-media` contains the exact inspected new image bytes. `previous-browser-media` retains the previous seven images, manifest and provenance byte-for-byte. The before/replacement approved-asset inventories preserve the local asset publication transition. Historical media was not rebound to the new source hash.

The original compiler artifacts and raw command logs remain under `.cache/public-media-selfhost-20261101` for local investigation. Clean-checkout public builds use the retained report, review and published image hash inventory; they do not require the compiler cache or test browser.
