# Android signing certificate search - 2026-06-23

## Finding

The Play-installed `app.cool.mobile` package certificate SHA-256 captured from the Pixel QA target is:

`45:17:38:E6:9A:DF:1B:4D:3F:AA:7A:65:90:20:28:2E:02:7B:47:86:26:71:C9:FC:32:45:AF:82:2B:4D:2A:92`

No matching readable local signing keystore, APK, or AAB was found on the Mac or the mounted `PRO-G40` SSD during this pass.

## Evidence searched

- Spotlight metadata search for `.jks`, `.keystore`, `.p12`, `.pfx`, `.apk`, `.aab`, `.pem`, `.crt`, and `.cer`.
- `rg --files` search across `/Users/jeanbosco` and `/Volumes/PRO-G40` for Android signing artifacts and `key.properties`.
- Follow-up full-machine/SSD search across internal user paths and mounted `PRO-G40` SSD volumes, including `/Users/jeanbosco`, `/Volumes/PRO-G40`, `/Volumes/PRO-G40-CS`, `/Volumes/PRO-G40-CS 1`, `/Library/Application Support`, `/Library/Preferences`, and `/private/etc`.
- Direct `key.properties` walk across `/Users` and `/Volumes` to derive local keystore paths.
- Direct certificate extraction for readable APK, AAB, and keystore candidates.
- Fingerprint text search across `/Users/jeanbosco` and `/Volumes/PRO-G40`.

Generated local evidence files:

- `.cache/signature_search/20260622T235755Z_whole_machine/search_scope.txt`
- `.cache/signature_search/20260622T235755Z_whole_machine/mdfind_candidates.txt`
- `.cache/signature_search/20260622T235755Z_whole_machine/rg_candidates.txt`
- `.cache/signature_search/20260622T235755Z_whole_machine/android_signing_focused/summary.txt`
- `.cache/signature_search/20260622T235755Z_whole_machine/android_signing_focused/candidates.txt`
- `.cache/signature_search/20260622T235755Z_whole_machine/android_signing_focused/signature_text_search_scoped.txt`
- `.cache/signature_search/mdfind-files.txt`
- `.cache/signature_search/rg-android-files.txt`
- `.cache/signature_search/key-properties-files.txt`
- `.cache/signature_search/android-signing-final-cert-report.txt`
- `.cache/signature_search/keyprops-derived-keystore-cert-report.txt`
- `.cache/signature_search/*-match-report.txt`

## Readable non-matching signing certificates

- `android/upload-keystore.jks`: `9E:E1:21:72:C7:8A:8A:48:79:06:D9:15:9B:FD:D1:7B:4D:78:AB:A3:54:1F:17:B4:10:65:9E:6D:60:DD:CC:10`
- `/Users/jeanbosco/repos/ibimina_gemini/apps/mobile-app/android/app/upload-keystore.jks`: `7A:CD:69:7B:5E:1C:71:18:54:BE:C2:0E:2D:B0:9F:19:6B:AA:7D:90:3B:1B:4F:12:21:AA:CD:CA:7C:72:16:F3`
- `/Volumes/PRO-G40/KANDA/android/keystore/upload-keystore.jks`: `FC:EE:A3:62:CB:0E:21:AA:20:55:E9:6E:0F:C9:80:1F:22:24:47:CA:DC:A6:76:8F:33:9E:8D:AB:3F:C6:D9:99`
- Flutter debug keystores: `4D:FD:5D:24:A2:BE:94:8E:39:C2:3D:D1:84:B3:E6:A1:BD:93:F2:D6:31:A1:C9:6A:1F:F2:D7:05:32:7C:06:0F`
- Local debug APK outputs: `5F:22:F9:CE:04:4F:C8:7C:35:46:D7:58:9B:EE:0C:8F:CC:D7:EF:97:20:B7:2B:6A:87:1A:94:CE:E0:C5:CE:88`
- `/Users/jeanbosco/Desktop/gikundiro_upload_certificate.pem`: `18:0C:F8:B8:D4:F0:A5:A3:8D:51:D9:C9:E2:FF:51:23:FB:49:CD:CE:6D:93:BD:01:08:E1:D1:29:86:97:D5:10`
- Other readable project keystores on `PRO-G40` also did not match, including BioPay, DINEIN, FANZONE, GASLINE, KANDA, LIKA, MEMORIES, MOBI, and ibimina-derived stores.

The expanded search tested 53 Android-signing-relevant candidate files, 4 `key.properties` files, 3 readable keystore fingerprints, 7 readable Android artifact fingerprints, and 13 public certificate fingerprints. None matched the Play-installed package fingerprint.

## Repo behavior after fix

`android/app/build.gradle.kts` now refuses production release and production-debug packaging when production signing material is missing or when the configured signing certificate does not match the expected Play certificate. This prevents installing a locally built `app.cool.mobile` package over the Play-installed app with the wrong signature.

To perform physical-device QA over the Play-installed package, provide the actual Play app-signing/original release keystore locally through `android/key.properties` or `COOL_ANDROID_*` environment variables. The expected non-secret fingerprint is documented in `android/key.properties.example`. The repo must not be pointed at `android/upload-keystore.jks` for production overwrite QA because that key does not match the Play-installed package signature.

## Validation

- `./gradlew :app:packageProductionDebug --console=plain` fails closed because the configured local signing certificate is `9EE12172C78A8A487906D9159BFDD17B4D78ABA3541F17B410659E6D60DDCC10`, not `451738E69ADF1B4D3FAA7A659020282E027B47862671C9FC3245AF822B4D2A92`.
- `./gradlew :app:assembleProductionRelease --console=plain` fails closed for the same mismatch.
- `./gradlew :app:assembleDevDebug --console=plain` succeeds, proving non-production development builds are not blocked by the Play signing guard.
