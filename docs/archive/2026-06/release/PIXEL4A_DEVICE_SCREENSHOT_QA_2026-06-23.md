# Pixel 4a device screenshot QA - 2026-06-23

## Scope

Device: Pixel 4a `13111JEC215558`, Android 13, physical size `1080x2340`, density `440`.

Build used for safe screenshot QA: `dev` flavor, package `app.cool.mobile.dev`.

Production package overwrite status: blocked by signing certificate mismatch until the Play app-signing/original release key is available locally. See `docs/release/ANDROID_SIGNING_CERTIFICATE_SEARCH_2026-06-23.md`.

## Evidence

- Manual startup/auth screenshots: `.cache/pixel4a_device_qa/20260622T233057Z/`
- Native launch splash after Android resource fix: `.cache/pixel4a_device_qa/20260623T004428Z_dev_cold_start_periwinkle_splash/`
- Release-mode Pixel cold start after the native splash fix: `.cache/pixel4a_device_qa/20260623T005226Z_dev_release_second_cold_start/`
- Full physical route screenshot run after the native splash fix: `.cache/android_route_visual_evidence/20260623T005320Z/`
- Mobile contact sheet: `.cache/android_route_visual_evidence/20260623T005320Z/contact_sheets/collect-mobile-route-contact-sheet.png`
- Route screenshot summary: `.cache/android_route_visual_evidence/20260623T005320Z/screenshots/summary.json`
- Device UAT log: `.cache/android_route_visual_evidence/20260623T005320Z/android_device_uat/android_device_uat.txt`

## Findings fixed in this pass

- Native startup splash no longer shows the white/paper screen or white square behind the mark. Android launch resources now use `@color/collect_launch_background` (`#8885F0`) plus transparent Collect PNG splash assets, matching the Pixel capture in `.cache/pixel4a_device_qa/20260623T004428Z_dev_cold_start_periwinkle_splash/01_startup_0450ms.png`.
- Flutter launch/root route no longer paints only the content-width area. `LaunchSplashScreen` now forces the background to full viewport with `SizedBox.expand`.
- Startup SMS/notification sync no longer runs when SMS feature flags are disabled, reducing unnecessary startup work in default/dev/evidence builds.
- Production/debug packaging now fails closed when the configured Android signing key does not match the Play-installed package certificate.
- A stale `app.cool.mobile.dev` install with an incompatible local signature was removed and replaced only for dev-device QA. The production package was not uninstalled or overwritten.

## Remaining issues

- Production physical-device overwrite remains blocked because no local readable signing key matched the Play-installed certificate.
- Pixel debug/evidence and first-install runs can show startup/render jank, but the second no-install `devRelease` cold start did not reproduce Collect-owned skipped-frame/Davey lines and reported `TotalTime: 314`, `WaitTime: 322`, `Displayed +314ms`, and `Fully drawn +314ms`:
  - `Skipped 159 frames`
  - `Skipped 56 frames`
  - `Davey! duration=963ms`
- The first `devRelease` run after install also contained a `Skipped 146 frames` line from `com.dropbox.android`, not from Collect. The Collect process in that same run had one launch-time `Skipped 62 frames` line and reached `Displayed/Fully drawn +1s423ms`; the clean second run is the better app-owned startup signal.
- Manual screenshots include the Android accessibility floating button overlay. That is OS-level state, not an app-rendered component, but future visual QA should disable it or move it away before capture.

## Route screenshot review

All 58 expected route screenshots were captured on the physical Pixel route run. No route was missing and no screenshot was below the minimum byte threshold.

| Screen | Route | Screenshot | Review |
| --- | --- | --- | --- |
| root-redirect | `/` | `mobile_route_root-redirect.png` | Pass after fix: full-screen launch background, transparent mark, no split background. |
| onboarding | `/onboarding` | `mobile_route_onboarding.png` | Pass: onboarding content renders; dense card stack is visible and scrollable. |
| onboarding-legal | `/onboarding/legal` | `mobile_route_onboarding-legal.png` | Pass: redirects to auth as expected. |
| auth | `/auth` | `mobile_route_auth.png` | Pass: phone entry and CTA render with semantics; no OTP sent during QA. |
| auth-success | `/auth/success` | `mobile_route_auth-success.png` | Pass: success state renders and CTA is visible. |
| auth-failure | `/auth/failure` | `mobile_route_auth-failure.png` | Pass: failure state renders and retry CTA is visible. |
| profile | `/settings/profile` | `mobile_route_profile.png` | Pass: MoMo/profile setup controls render. |
| profile-readiness | `/settings/readiness` | `mobile_route_profile-readiness.png` | Pass: readiness summary renders. |
| sms-permission-redirect | `/permissions/sms` | `mobile_route_sms-permission-redirect.png` | Pass: redirects into SMS access-needed state. |
| sms-denied | `/permissions/sms-denied` | `mobile_route_sms-denied.png` | Pass: denied state renders. |
| device-permission | `/permissions/device` | `mobile_route_device-permission.png` | Pass: app access panel renders. |
| notifications-denied | `/permissions/notifications-denied` | `mobile_route_notifications-denied.png` | Pass: notification blocked state renders. |
| camera-denied | `/permissions/camera-denied` | `mobile_route_camera-denied.png` | Pass: camera blocked state renders. |
| home | `/home` | `mobile_route_home.png` | Pass: main dashboard renders with bottom nav. |
| groups | `/groups` | `mobile_route_groups.png` | Pass: group list renders with bottom nav. |
| groups-search | `/groups/search` | `mobile_route_groups-search.png` | Pass: search/empty state renders. |
| group-create | `/groups/create` | `mobile_route_group-create.png` | Pass: create form renders. |
| group-scan | `/groups/scan` | `mobile_route_group-scan.png` | Pass: QR scanner shell renders; camera feed is fixture/black in test mode. |
| iphone-create-unavailable | `/platform/iphone-create-unavailable` | `mobile_route_iphone-create-unavailable.png` | Pass: unavailable state renders. |
| group-detail | `/groups/col-church` | `mobile_route_group-detail.png` | Pass: group detail renders. |
| group-created | `/groups/col-church/created` | `mobile_route_group-created.png` | Pass: created confirmation renders. |
| group-joined | `/groups/col-church/joined` | `mobile_route_group-joined.png` | Pass: joined confirmation renders. |
| join | `/groups/join` | `mobile_route_join.png` | Pass: join group form renders. |
| owner-redirect | `/groups/col-church/owner` | `mobile_route_owner-redirect.png` | Pass: owner settings renders. |
| owner-sms-health-redirect | `/groups/col-church/owner/sms-health` | `mobile_route_owner-sms-health-redirect.png` | Pass: owner settings renders. |
| owner-receiver-redirect | `/groups/col-church/owner/receiver` | `mobile_route_owner-receiver-redirect.png` | Pass: owner settings renders. |
| share | `/groups/col-church/share` | `mobile_route_share.png` | Pass: QR/share screen renders. |
| invite | `/groups/col-church/invite` | `mobile_route_invite.png` | Pass: invite landing screen renders. |
| shared-group-link | `/c/st-michel-building-fund` | `mobile_route_shared-group-link.png` | Pass: shared link renders. |
| share-invalid | `/share/invalid` | `mobile_route_share-invalid.png` | Pass: invalid link state renders. |
| share-expired | `/share/expired` | `mobile_route_share-expired.png` | Pass: expired link state renders. |
| share-expired-request | `/share/expired/request` | `mobile_route_share-expired-request.png` | Pass: expired request state renders. |
| share-confirmed-redirect | `/share/confirmed` | `mobile_route_share-confirmed-redirect.png` | Pass: redirects to app entry/dashboard. |
| app-share-entry | `/app` | `mobile_route_app-share-entry.png` | Pass: app entry renders dashboard. |
| app-invite-link | `/invite/038491` | `mobile_route_app-invite-link.png` | Pass: invite entry renders dashboard. |
| contribution | `/groups/col-church/contribute` | `mobile_route_contribution.png` | Pass: contribution form renders. |
| payment-handoff-redirect | `/groups/col-church/pay/intent-render/handoff` | `mobile_route_payment-handoff-redirect.png` | Pass: payment handoff renders. |
| payment-intent | `/groups/col-church/pay/intent-render` | `mobile_route_payment-intent.png` | Pass: payment intent renders. |
| payment-waiting | `/groups/col-church/pay/intent-render/waiting` | `mobile_route_payment-waiting.png` | Pass: waiting state renders. |
| payment-pending | `/groups/col-church/pay/intent-render/state/pending` | `mobile_route_payment-pending.png` | Pass: pending state renders. |
| payment-confirmed | `/groups/col-church/pay/intent-render/state/confirmed` | `mobile_route_payment-confirmed.png` | Pass: confirmed state renders. |
| payment-expired | `/groups/col-church/pay/intent-render/state/expired` | `mobile_route_payment-expired.png` | Pass: expired state renders. |
| payment-needs-review | `/groups/col-church/pay/intent-render/state/needs-review` | `mobile_route_payment-needs-review.png` | Pass: needs-review state renders. |
| payment-support-review | `/groups/col-church/support/payment/intent-render` | `mobile_route_payment-support-review.png` | Pass: support review state renders. |
| ledger | `/groups/col-church/ledger` | `mobile_route_ledger.png` | Pass: ledger renders. |
| manage | `/groups/col-church/manage` | `mobile_route_manage.png` | Pass: group management renders. |
| group-profile | `/groups/col-church/profile` | `mobile_route_group-profile.png` | Pass: group profile renders. |
| members | `/groups/col-church/members` | `mobile_route_members.png` | Pass: members list renders. |
| settings | `/settings` | `mobile_route_settings.png` | Pass: settings hub renders. |
| account | `/settings/account` | `mobile_route_account.png` | Pass: account settings render. |
| account-delete | `/settings/account/delete` | `mobile_route_account-delete.png` | Pass: delete request screen renders. |
| privacy | `/settings/privacy` | `mobile_route_privacy.png` | Pass: privacy screen renders. |
| legal-privacy | `/settings/legal/privacy` | `mobile_route_legal-privacy.png` | Pass: privacy policy renders. |
| legal-terms | `/settings/legal/terms` | `mobile_route_legal-terms.png` | Pass: terms screen renders. |
| help | `/settings/help` | `mobile_route_help.png` | Pass: support screen renders. |
| notifications | `/notifications` | `mobile_route_notifications.png` | Pass: notifications screen renders. |
| offline | `/offline` | `mobile_route_offline.png` | Pass: connection issue screen renders. |
| sync | `/sync` | `mobile_route_sync.png` | Pass: sync status screen renders. |
