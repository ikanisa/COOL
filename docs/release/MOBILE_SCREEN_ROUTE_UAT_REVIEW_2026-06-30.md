# Mobile Screen Route UAT Review - 2026-06-30

Repo: `/Volumes/PRO-G40/COOL`
Scope: member Flutter app routes after redundant-screen cleanup.

## Current Route Model

The member app keeps exactly three bottom navigation destinations:

| Destination | Route | Purpose |
| --- | --- | --- |
| Home | `/home` | Overview, balances, activity, and quick entry into groups. |
| Groups | `/groups` | Group list, QR scan, create flow, and group navigation. |
| Settings | `/settings` | Profile, account, privacy, legal, support, and app preferences. |

The product route inventory is now intentionally small. Native OS prompts or app-settings sheets replace standalone permission screens.

## Kept Screens

| Route name | Route | Why it remains |
| --- | --- | --- |
| root | `/` | App entry/splash. |
| auth | `/auth` | OTP/auth entry. |
| profile-edit | `/settings/profile` | Edit profile and MoMo receiver details. |
| home | `/home` | Primary overview. |
| groups | `/groups` | Primary group list and actions. |
| group-create | `/groups/create` | Android owner group creation only; iPhone create action is hidden. |
| group-scan | `/groups/scan` | QR/deep-link join. Camera recovery opens native settings sheet. |
| group-detail | `/groups/:collectionId` | Main group surface. |
| share | `/groups/:collectionId/share` | QR/share invite surface. |
| invite | `/groups/:collectionId/invite` | Compatibility redirect to share. |
| shared-group-link | `/c/:slug` | External group link landing. |
| share-invalid | `/share/invalid` | Invalid link recovery. |
| share-expired | `/share/expired` | Expired link recovery. |
| share-expired-request | `/share/expired/request` | Request fresh invite link. |
| app | `/app` | Compatibility app entry redirect. |
| invite-public | `/invite/:publicId` | Compatibility invite redirect. |
| contribution | `/groups/:collectionId/contribute` | MoMo USSD launch for local groups; no local status screen. |
| ledger | `/groups/:collectionId/ledger` | Confirmed contribution/activity ledger. |
| manage | `/groups/:collectionId/manage` | Owner management. |
| group-profile | `/groups/:collectionId/profile` | Owner group profile/editing. |
| members | `/groups/:collectionId/members` | Member list. |
| settings | `/settings` | Primary settings menu. |
| account | `/settings/account` | Account/session controls. |
| account-delete | `/settings/account/delete` | Account deletion request. |
| privacy | `/settings/privacy` | Privacy/data controls. |
| legal-privacy | `/settings/legal/privacy` | Privacy policy. |
| legal-terms | `/settings/legal/terms` | Terms. |
| help | `/settings/help` | Help/support. |
| offline | `/offline` | Connectivity recovery. |
| sync | `/sync` | Sync recovery/status. |

## Deleted Screens

These routes and screen files must not return:

- Onboarding screens: `/onboarding`, `/onboarding/legal`.
- Permission screens: `/permissions/sms`, `/permissions/sms-denied`, `/permissions/device`, `/permissions/notifications-denied`, `/permissions/camera-denied`.
- iPhone create-unavailable screen: `/platform/iphone-create-unavailable`; iPhone users should not see create-group entry points.
- Join confirmation screen: `/groups/:collectionId/joined`; successful joins go straight to the group.
- Legacy owner redirect screens: `/groups/:collectionId/owner`, `/groups/:collectionId/owner/sms-health`, `/groups/:collectionId/owner/receiver`.
- Local MoMo payment status/support screens: `/groups/:collectionId/pay/:intentId`, `/groups/:collectionId/pay/:intentId/handoff`, `/groups/:collectionId/pay/:intentId/state/:state`, `/groups/:collectionId/support/payment/:intentId`.
- Notification center route: `/notifications`; notification recovery uses native settings.
- Share-confirmed redirect: `/share/confirmed`.

## Payment Rule

Local users use MoMo USSD outside the app. The contribution flow creates the internal record needed for SMS reconciliation, launches `tel:*182#`, then returns to the group. The app must not show pending, expired, review, confirmed, or support-review screens for local MoMo.

Stripe is diaspora-only. Diaspora groups are admin-created, so the member group-creation UI does not expose a diaspora selector. Stripe UI should only activate when a group is already marked as diaspora by admin/backend data.

## Validation Status

- Flutter fixture visual evidence now reads route specs from `scripts/mobile_route_render_smoke.sh`.
- Route evidence scripts and release evidence index use the reduced route list.
- Physical device UAT remains a release-signoff item when an authorized Android device or supported iOS device workflow is available.
