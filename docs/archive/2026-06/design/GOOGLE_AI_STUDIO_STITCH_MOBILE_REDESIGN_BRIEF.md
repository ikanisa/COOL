# Collect Mobile App Product Description For Google AI Studio / Stitch

Status: repo-backed product description  
Reviewed: 2026-05-31  
Repo: `/Volumes/PRO-G40/COOL`  
Flutter app: `collect_app`

## Purpose Of This Document

This document describes the Collect mobile app, its users, workflows, features, product rules, and current Flutter screen map so Google AI Studio / Stitch has enough context to redesign the mobile frontend from scratch.

It intentionally does not prescribe a visual style, component system, screen layout, color palette, or interaction pattern. Google AI Studio / Stitch should decide the best UI/UX direction from the product context.

## Product Summary

Collect is a mobile app for group MoMo collections. It helps people create or join groups, contribute money through MoMo, and see confirmed contribution records after MoMo SMS verification.

Collect does not hold money and is not a wallet. The group owner receives MoMo payments directly. The app creates contribution/payment intents and records verified contributions after official MoMo SMS notifications are captured, parsed, and allocated by the backend.

The core product is SMS-verified group contribution tracking:

1. A member joins or opens a group.
2. The member enters a contribution amount.
3. Collect creates a payment intent linked to the group, member, amount, receiver, and member Collect ID.
4. Collect opens the phone MoMo USSD dialer through a `tel:` link.
5. The member completes payment outside Collect.
6. The group owner's Android device receives the official MoMo SMS notification.
7. The SMS is uploaded to Supabase.
8. The backend parses the SMS with OpenAI structured extraction.
9. Supabase allocation logic matches the parsed payment to a pending payment intent.
10. The group ledger updates automatically.

## Product Name And Language

- Product name: `Collect`.
- Use `Groups` for the shared collection units.
- Do not use `Goals`.
- Currency: RWF.
- Payment context: MoMo / MTN MoMo / USSD.
- User identity: generated 6-digit `Collect ID`.

## User Roles

### Member

A signed-in person who can:

- sign in with WhatsApp OTP;
- receive or use a 6-digit Collect ID;
- add a MoMo number in profile/settings;
- join groups;
- contribute to groups through MoMo USSD;
- view contribution status and confirmed ledger entries.

### Group Owner

A member who creates a group on Android. A group owner can:

- create a group;
- use their profile MoMo number as the default receiver number;
- edit the receiver MoMo number during group creation;
- grant Android SMS access so Collect can capture official MoMo SMS notifications;
- share a group by link, QR code, SMS, WhatsApp/chat, and deep link;
- view group activity and confirmed ledger entries.

### Admin Operator

Admin operators work in a separate Flutter web Admin PWA, not the ordinary mobile member app. They monitor:

- SMS intake;
- parser health;
- payment intents;
- parsed transactions;
- allocation status;
- groups;
- members;
- exceptions;
- audit logs;
- system health.

Admin exception handling is not a member-side manual confirmation flow.

## Hard Product Constraints

These are product and compliance constraints that any redesigned app must preserve:

- Mobile primary navigation currently has exactly three areas: Home, Groups, Settings.
- Public/member identity is a generated 6-digit Collect ID.
- The app must not ask for real names.
- The app must not ask for display names.
- The app must not ask users to choose anonymity.
- The app must not ask contributors to paste SMS messages.
- The app must not ask contributors to enter transaction IDs.
- The app must not ask contributors to upload payment screenshots.
- The app must not ask contributors to manually confirm payment.
- Contribution status comes from backend payment-intent allocation and MoMo SMS verification.
- Raw SMS evidence is protected data.
- Phone numbers and MoMo numbers are protected data.
- Receiver MoMo details may be shown only where needed for a payment/payment-intent context.
- Group creation is Android-only because SMS access is required for owner-side automated capture.
- On iPhone, group creation is unavailable and the product message is exactly: `group creation is available only on Android`.
- Payment happens outside Collect through MoMo/USSD. Collect records, verifies, and allocates; it does not custody money.

## Technical Stack

- Flutter mobile app.
- Material 3 currently enabled.
- Riverpod for state management.
- GoRouter for route management.
- Supabase for authentication, database/RPC, realtime updates, and edge functions.
- WhatsApp OTP through Supabase Auth.
- Android SMS access/channel for owner-side MoMo SMS capture.
- OpenAI API is used server-side for structured SMS parsing.
- `url_launcher` opens MoMo USSD and external share targets.
- `qr_flutter` renders group QR codes.

## Current Flutter App Map

The mobile app is launched from:

- `lib/main.dart`
- `lib/app/app.dart`
- `lib/app/router.dart`
- `lib/core/widgets/collect_shell.dart`

Current user-facing routes:

| Route | Current screen | What it does |
| --- | --- | --- |
| `/auth` | `AuthScreen` | WhatsApp phone OTP sign-in. |
| `/home` | `HomeScreen` | Dashboard with total raised, group count, pending intents, recent groups, activity, and shortcuts. |
| `/groups` | `CollectionsScreen` | Lists groups and offers group creation. |
| `/groups/create` | `CollectionCreateScreen` | Creates a group with name, optional description, receiver MoMo number, and Android SMS access. |
| `/groups/:collectionId` | `CollectionDetailScreen` | Shows group details, amount raised, supporters, contribution/share/ledger actions, and activity. |
| `/groups/:collectionId/manage` | `CollectionManageScreen` | Owner management entry for share and ledger. |
| `/groups/:collectionId/contribute` | `ContributionFlowScreen` | Amount entry, payment intent creation, MoMo USSD launch. |
| `/groups/:collectionId/pay/:intentId` | `PaymentIntentStatusScreen` | Shows payment intent status while Collect waits for MoMo SMS allocation. |
| `/groups/:collectionId/share` | `ShareScreen` | Shares group by SMS, WhatsApp, copied link, and QR code. |
| `/groups/:collectionId/invite` | `InviteScreen` | Currently aliases the share screen. |
| `/groups/:collectionId/ledger` | `LedgerScreen` | Shows confirmed SMS-matched contribution records. |
| `/c/:slug` | `GroupLinkScreen` | Opens a group from a shared link/deep link. |
| `/settings` | `SettingsScreen` | Profile, MoMo number, SMS access, privacy boundary, debug catalog link in debug. |
| `/settings/profile` | `ProfileSetupScreen` | Shows Collect ID and collects/saves MoMo number under Settings. |
| `/dev/design-system` | `DesignSystemCatalogScreen` | Debug-only catalog of current UI tokens/components. |

## Main Product Workflows

### Sign In And Profile

The user signs in with a WhatsApp-capable phone number. After sign-in, the app shows or creates the user's generated 6-digit Collect ID. The user can save a MoMo number in profile/settings. That MoMo number is used as the default receiver number when the user creates groups.

The app should not collect real names or display names.

### Create Group

Group creation is for Android users because Android SMS access is needed for automated MoMo SMS capture. The group creator enters:

- group name;
- optional description;
- receiver MoMo number, prefilled from profile if available.

During group creation, the app requests/enables SMS access so official MoMo notifications can be captured for automated contribution records.

iPhone users can join and contribute to groups, but cannot create groups. The iPhone unavailable message must be exactly: `group creation is available only on Android`.

### Join Group

A user can join or open a group from:

- shared link;
- QR code;
- deep link;
- SMS share;
- WhatsApp/chat share.

The app identifies the user by authenticated profile and Collect ID. It does not ask for a real name or anonymity setting.

### Contribute

The user opens a group, enters an amount in RWF, and taps `Contribute`. The app creates a payment intent that includes:

- group id;
- member user id;
- member 6-digit Collect ID;
- amount;
- receiver MoMo number;
- pending status;
- expiry/reconciliation metadata.

After the payment intent is created, Collect opens the MoMo USSD dialer with a `tel:` link. The member completes the MoMo payment outside Collect.

Collect does not ask the member to manually report the payment afterward.

### Payment Status

After contribution initiation, the app shows the payment intent status. The user needs to understand that:

- the payment was initiated outside Collect through MoMo;
- Collect is waiting for official receiver MoMo SMS evidence;
- backend allocation will update the payment and ledger automatically;
- no manual SMS paste or transaction reference entry is needed.

### Automated SMS Capture

On the Android group owner's device:

- official MoMo SMS notifications are received;
- matching messages are queued locally;
- queued SMS is uploaded to Supabase;
- Supabase stores protected raw SMS evidence;
- OpenAI structured parsing extracts payment facts;
- database allocation logic matches parsed transactions to pending payment intents.

### Ledger

The ledger shows confirmed contributions after backend allocation. Ledger entries use safe member labels such as Collect ID. Raw SMS, full phone numbers, and protected evidence are not shown in normal member screens.

### Share Group

Groups can be shared through:

- link;
- QR code;
- deep link;
- SMS;
- WhatsApp/chat;
- native share target where supported.

Shared links should not contain phone numbers, receiver MoMo numbers, or raw SMS data.

### Settings

Settings/profile contains:

- Collect ID;
- WhatsApp login phone;
- MoMo number;
- SMS access status where relevant;
- privacy/support/legal areas where relevant.

## Product Data Concepts

The app currently uses these core models:

- `CollectProfile`: user id, 6-digit public Collect ID, WhatsApp phone, optional MoMo number.
- `CollectCollection`: group id, slug, creator user id, title, description, receiver MoMo number, receiver label, created date.
- `CollectionSummary`: amount raised in RWF and supporter count.
- `PaymentIntentModel`: id, group id, member Collect ID linkage, expected RWF amount, receiver label, receiver MoMo number, network, status, created/expiry dates.
- `Contribution`: confirmed posted amount, safe supporter label, created date, optional transaction id.
- `ParsedPaymentEvent`: backend/admin concept for parsed SMS facts, confidence, allocation status, transaction id, amount.

## Current Sample Data

Use these as realistic sample values if needed:

- Product: Collect
- Collect ID: `038491`
- WhatsApp phone: `+250788123456`
- MoMo number: `+250788123456`
- Group: `St Michel building fund`
- Group description: `Transparent support for materials, labor, and weekly updates from the building committee.`
- Receiver label: `St Michel treasury`
- Group: `Kigali Lions away kit`
- Group description: `Fans are helping the team buy away jerseys and travel supplies for next month.`
- Contribution amount: `RWF 5,000`
- Raised amount: `RWF 35,000`
- Transaction id example: `MTN12345`
- Network: `MTN MoMo`
- Payment intent status: `pending`

## Current Frontend Situation

The current mobile frontend exists and is functional. It already has routes, mocked/seeded local data, Supabase integration points, tests, and a basic shared component system.

The current design is not considered good enough. It should be redesigned from scratch at the frontend/UI/UX level. Google AI Studio / Stitch should use this product description to decide the best:

- information architecture;
- screen set;
- user journeys;
- layout system;
- visual language;
- interaction model;
- mobile UI patterns;
- frontend component approach.

The redesign should not be constrained by the current look of the Flutter widgets. The current route list and workflows are provided as product context, not as a requested screen layout.

## Open Prompt For Google AI Studio / Stitch

Paste this into Google AI Studio / Stitch:

```text
I need a complete mobile app frontend redesign for an existing Flutter app called Collect.

Please use the product description below as context and decide the best UI/UX, screen structure, interaction model, visual direction, and mobile frontend experience. Do not simply copy the current app structure or current UI. Redesign the frontend from scratch based on the product, users, workflows, and constraints.

Product:
Collect is a mobile app for group MoMo collections. It helps people create or join groups, contribute money through MoMo, and see confirmed contribution records after MoMo SMS verification.

Collect is not a wallet and does not custody money. The group owner receives MoMo payments directly. Collect creates payment intents and records verified contributions after official MoMo SMS notifications are captured, parsed, and allocated by the backend.

Core workflow:
1. A member joins or opens a group.
2. The member enters a contribution amount in RWF.
3. Collect creates a payment intent linked to the group, member, amount, receiver, and member Collect ID.
4. Collect opens the phone MoMo USSD dialer through a tel link.
5. The member completes payment outside Collect.
6. The group owner's Android device receives the official MoMo SMS notification.
7. The SMS is uploaded to Supabase.
8. The backend parses the SMS with OpenAI structured extraction.
9. Supabase allocation logic matches the parsed payment to a pending payment intent.
10. The group ledger updates automatically.

Users:
- Member: signs in, gets a 6-digit Collect ID, joins groups, contributes, sees payment status and ledger records.
- Group owner: creates groups on Android, grants SMS access, receives MoMo payments directly, shares groups, sees group activity.
- Admin operator: uses a separate web Admin PWA for SMS intake, parser health, allocations, exceptions, audit logs, and system health. Admin is not the ordinary mobile member experience.

Important product rules:
- Product name is Collect.
- Use the word Groups, not Goals.
- Currency is RWF.
- Payment context is MoMo / MTN MoMo / USSD.
- Public/member identity is a generated 6-digit Collect ID.
- Do not ask for real names, display names, avatars, or anonymity choices.
- Do not ask contributors to paste SMS messages.
- Do not ask contributors to enter transaction IDs.
- Do not ask contributors to upload payment screenshots.
- Do not ask contributors to manually confirm payment.
- Contribution status comes from backend payment-intent allocation and MoMo SMS verification.
- Raw SMS evidence is protected data.
- Phone numbers and MoMo numbers are protected data.
- Receiver MoMo details may be shown only where needed for a payment/payment-intent context.
- Group creation is Android-only because SMS access is required for owner-side automated capture.
- On iPhone, group creation is unavailable and the product message is exactly: "group creation is available only on Android".
- Payment happens outside Collect through MoMo/USSD. Collect records, verifies, and allocates; it does not custody money.

Key features:
- WhatsApp OTP sign-in.
- Generated 6-digit Collect ID.
- Profile/settings with MoMo number.
- Groups list and group detail.
- Android-only group creation.
- SMS access/consent for Android group owners.
- Join group through shared link, QR code, deep link, SMS, or WhatsApp/chat.
- Contribution amount entry.
- Payment intent creation.
- MoMo USSD launch.
- Payment intent status while waiting for SMS verification/allocation.
- Confirmed ledger entries.
- Group sharing through link, QR, SMS, WhatsApp/chat, and native share.
- Settings/profile/privacy/support areas.

Current app areas for context:
- Auth / WhatsApp OTP
- Profile setup
- Home/dashboard
- Groups list
- Create group
- Group detail
- Manage group
- Contribute
- Payment intent status
- Share/invite
- Shared group link opening
- Ledger
- Settings

Sample content:
- Collect ID: 038491
- Group: St Michel building fund
- Description: Transparent support for materials, labor, and weekly updates from the building committee.
- Receiver label: St Michel treasury
- Group: Kigali Lions away kit
- Description: Fans are helping the team buy away jerseys and travel supplies for next month.
- Amount: RWF 5,000
- Raised: RWF 35,000
- Transaction example: MTN12345
- Network: MTN MoMo
- Status: pending

Task:
Based on this app description, create the best possible full mobile frontend redesign for Collect. Decide the screen set, user flow, UI/UX patterns, hierarchy, visual style, and interaction model yourself. The goal is a strong, production-quality mobile app experience for the entire frontend, not a minor refresh of the existing screens.
```

## Implementation Context For Later Flutter Work

After Google AI Studio / Stitch produces a redesign, the Flutter implementation will need to preserve existing product behavior and backend contracts:

- app entry: `lib/main.dart`;
- app shell/router: `lib/app/app.dart`, `lib/app/router.dart`, `lib/core/widgets/collect_shell.dart`;
- theme files: `lib/app/theme/collect_*.dart`;
- shared widgets: `lib/shared/widgets/`;
- screens: `lib/features/auth`, `lib/features/profile`, `lib/features/home`, `lib/features/collections`, `lib/features/payments`, `lib/features/ledger`, `lib/features/settings`;
- state/data: `lib/shared/repositories/collect_repository.dart`, `lib/shared/models/collect_models.dart`;
- admin PWA entry: `lib/main_admin.dart`.

The Flutter implementation should follow the redesign output while keeping the product constraints and backend workflows above.
