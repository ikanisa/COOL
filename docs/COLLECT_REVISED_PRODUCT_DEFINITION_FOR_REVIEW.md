# Collect Revised Product Definition, Journeys, Workflows, And UI/UX

Status: Draft for owner review  
Date: 2026-05-27  
Purpose: Replace the incorrect prior product framing before implementation begins. This document is the proposed guiding product definition for the Collect/Cool refactor. It is not yet an implementation record.

## Source Of Truth

Collect is a mobile-money group collection app. The core product is automated SMS-based MoMo contribution capture and allocation.

The target workflow must follow the proven PayLedger pattern:

1. Android app receives official MoMo SMS notifications after SMS permission approval.
2. The app stores each matching SMS in a local durable queue.
3. The app signs and uploads queued SMS batches to a Supabase Edge Function.
4. Supabase stores immutable raw SMS evidence.
5. Supabase Edge Function uses OpenAI API structured parsing to extract transaction facts.
6. Database logic validates the parser result and creates transaction rows.
7. Allocation logic links each parsed transaction to the member payment intent created when the member tapped `Contribute`.
8. The payment intent carries the group, amount, receiver MoMo number, member profile, and generated 6-digit Collect ID, so Supabase can allocate the parsed payment to the right member.
9. Mobile app and Admin PWA update from Supabase realtime allocation events.

There must be no manual SMS paste workflow, no manual MoMo instruction screen, no user-reported transaction ID workflow, and no user choice of anonymity during contribution.

## Product Definition

Collect helps people create and contribute to groups where the group owner receives MoMo payments directly. The app records contributions automatically by reading MoMo SMS notifications on the Android device that owns the group receiver number.

Collect does not ask users for real names. Every user receives an automatically generated 6-digit Collect ID. Public and member-facing identity is always anonymous by default and represented by the Collect ID where needed.

The app is not a general wallet and does not custody money. Payment happens through the phone's MoMo USSD flow. Collection evidence is created after the group owner receives an official MoMo SMS and the backend parses and allocates it.

## Non-Negotiable Product Rules

- Identity: no real name collection, no display-name requirement, no user-selected anonymity setting.
- User ID: every user has an auto-generated 6-digit Collect ID.
- Privacy: users are anonymous by default; do not expose full phone or MoMo numbers in normal group views.
- Profile: MoMo number is managed once in profile/settings and reused across group creation and contribution.
- Group language: use `Groups`, not `Active goals`.
- Navigation: only three bottom tabs: `Home`, `Groups`, and `Settings`.
- Group creation: Android only because SMS access is required for owner-side automated contribution capture.
- iPhone rule: iPhone users can join and contribute, but cannot create groups. The create group button is always inactive on iPhone; tapping it shows exactly: `group creation is available only on Android`.
- SMS access: when an Android user creates their first group, SMS app access permission/consent is triggered as part of the group creation flow.
- Payment initiation: contributors enter amount and tap `Contribute`; Supabase creates a payment intent linked to the member's 6-digit Collect ID, then the app opens the MoMo USSD dialer through a `tel:` link. The contributor completes the payment outside the app with MoMo PIN.
- Confirmation: payment confirmation is not entered by the contributor. It arrives through the group owner's MoMo SMS and is processed by Supabase/OpenAI/allocation logic.
- No fallback manual SMS input in the member app.
- No category, target amount, cover URL, public directory, or campaign-style fundraising flow in the simplified group creation journey unless explicitly reintroduced later.

## Core Roles

### User

Any signed-in person. A user can:

- Sign in with WhatsApp OTP using any supported phone number, not Rwanda-only.
- Maintain profile settings.
- Add or update their MoMo number in profile.
- Join groups.
- Contribute to groups through MoMo USSD.
- See their groups and contribution status through anonymous/ID-based records.

### Group Owner

A user who creates a group on Android. A group owner:

- Must have a profile MoMo number.
- Must grant Android SMS access for automated MoMo SMS capture.
- Receives group contributions on their synced group receiver MoMo number.
- Can edit the receiver MoMo number during group creation if needed.
- Shares groups through link, QR code, deep link, chat apps, SMS, and other native share targets.
- Does not manually paste SMS or manually confirm transactions.

### Admin Operator

Admin operators work in the Admin PWA. They monitor and control the automated backend pipeline:

- SMS intake and parser health.
- Raw SMS evidence status.
- Parsed transaction listing.
- Allocation status.
- Groups and members.
- Exceptions where automation cannot safely allocate.
- Audit logs and operational health.

Admin exception handling is not a user fallback flow. It is an operational control for low-confidence, invalid, duplicate, or ambiguous backend events.

## Main App Information Architecture

The mobile app should have exactly three bottom navigation destinations:

1. Home
2. Groups
3. Settings

Everything else must be nested under one of these three areas.

### Home

Home is the landing dashboard. It should show:

- Simple greeting and user Collect ID.
- Recent group activity.
- Pending contribution status where relevant.
- Quick access to latest groups.
- SMS automation health if the user owns Android-created groups.
- Short trust/status notices only when action is needed.

Home must not use `Active goals`.

### Groups

Groups is the primary product surface. It should include:

- My groups.
- Joined groups.
- Create group action.
- Group detail.
- Member list using Collect IDs.
- Contribution initiation.
- Group sharing by link, QR code, native share sheet, chat apps, and SMS.
- Group transaction/activity listing.
- Owner SMS automation status for owner-created groups.

### Settings

Settings owns all account/profile/platform configuration:

- Profile.
- Auto-generated 6-digit Collect ID.
- WhatsApp login phone.
- MoMo number.
- SMS access status on Android.
- Device/platform status.
- Admin access link only if applicable.
- Legal/privacy/support entries.

Settings is where MoMo number and privacy defaults live. Users should not repeat those fields in group creation, joining, or contribution flows.

## User Journeys

### Journey 1: Sign In And Profile Setup

1. User opens Collect.
2. User signs in with WhatsApp OTP.
3. App supports any valid WhatsApp-capable phone number; it is not Rwanda-only at login.
4. Backend assigns or fetches the user's 6-digit Collect ID.
5. User goes to Settings/Profile.
6. User adds their MoMo number.
7. The MoMo number becomes the default number for group ownership and member matching.

No real name is requested. No anonymity choice is shown.

### Journey 2: Android User Creates First Group

1. User taps `Groups`.
2. User taps `Create group`.
3. App checks platform.
4. If Android:
   - app checks whether profile MoMo number exists;
   - if missing, user is sent to Settings/Profile to add MoMo number;
   - app explains SMS access is required because Collect records contributions from official MoMo SMS notifications;
   - Android SMS permission request is triggered.
5. User creates group with:
   - group name;
   - optional description;
   - receiver MoMo number prefilled from profile;
   - option to edit receiver MoMo number.
6. Group is created.
7. Receiver MoMo number is stored for the group.
8. Android SMS monitoring is active for official MoMo sender IDs.
9. Group creator can share the group by link, QR code, deep link, chat app, SMS, or the native share sheet.

No category, target amount, cover URL, anonymity choice, or manual SMS screen is part of this journey.

### Journey 3: iPhone User Sees Disabled Group Creation

1. iPhone user taps `Groups`.
2. `Create group` is inactive.
3. If the user taps it, app shows exactly: `group creation is available only on Android`.

### Journey 4: User Joins A Group

1. User receives a group link, QR code, deep link, chat-app share, or SMS share.
2. User opens the group from that shared entry point.
3. App identifies the user by Collect ID and authenticated profile.
4. User joins.
5. User's profile MoMo number is used for future allocation matching where applicable.

The user is not asked for a real name or anonymity setting.

### Journey 5: User Contributes To A Group

1. User opens a group.
2. User taps `Contribute`.
3. User enters amount.
4. User taps the contribution button.
5. Supabase creates a payment intent with:
   - group ID;
   - member user ID;
   - member 6-digit Collect ID;
   - amount;
   - receiver MoMo number;
   - pending status;
   - expiry/reconciliation metadata.
6. App launches the phone dialer with a MoMo USSD `tel:` link. Receiver and amount remain visible in Collect while the user completes the provider flow outside the app.
7. User completes payment outside Collect with MoMo PIN.
8. User returns to Collect.
9. App does not ask for a transaction ID.
10. When the group owner receives the official MoMo SMS, Supabase parses it and allocates it against the pending payment intent.
11. Mobile app receives Supabase realtime updates for payment intent, allocation, and group activity.

### Journey 6: Automated SMS Capture On Android Owner Device

1. MoMo sends an official payment SMS to the Android group owner's phone.
2. Android SMS receiver listens for `SMS_RECEIVED`.
3. App filters by approved MoMo sender IDs.
4. Matching SMS is written to a local queue with:
   - raw SMS body;
   - sender;
   - received timestamp;
   - canonical hash;
   - user/gateway identity.
5. WorkManager sync uploads queued SMS to Supabase.
6. Upload is authenticated and signed.
7. Retry/backoff handles offline or temporary failure.

This mirrors PayLedger's Android gateway pattern.

### Journey 7: Supabase/OpenAI Parsing

1. Supabase Edge Function receives signed SMS batch.
2. Function verifies:
   - Supabase auth/JWT;
   - gateway or device ownership;
   - request signature;
   - timestamp freshness;
   - nonce replay protection;
   - batch schema;
   - canonical SMS hash;
   - approved sender ID.
3. Function writes immutable raw SMS evidence.
4. Function calls OpenAI API with structured output schema.
5. Parser extracts only evidence supported by the SMS:
   - amount;
   - currency;
   - transaction reference;
   - payer phone/identifier if present;
   - transaction timestamp;
   - network;
   - direction;
   - confidence.
6. Backend validates the parser output.
7. Valid inbound payment SMS creates a transaction row.
8. Supabase attempts to match the transaction to a pending payment intent for the same group/receiver/amount/member context.
9. Invalid, non-payment, duplicate, low-confidence, unsupported, or ambiguous SMS does not create a posted member contribution.

### Journey 8: Payment-Intent-Based Allocation To Member

1. Transaction insert triggers allocation logic.
2. Allocation is based first on the pending payment intent created when the member tapped `Contribute`.
3. The payment intent links:
   - group ID;
   - member user ID;
   - member 6-digit Collect ID;
   - amount;
   - receiver MoMo number;
   - pending contribution state.
4. Parsed SMS transaction facts are matched against pending payment intents for the group receiver.
5. If exactly one payment intent matches safely, allocation posts to that member.
6. The member/group ledger updates automatically.
7. Supabase realtime publishes allocation updates to the mobile app and Admin PWA.
8. If no safe payment-intent match exists, the event goes to an admin exception queue.

Important identity rule: no member-facing real names. Allocation must rely on Collect ID, payment intent, group membership, amount, receiver MoMo number, and protected payment evidence. Provider-supplied payer names from SMS must not become member identity.

### Journey 9: Admin Operations

Admin PWA must explain and operate the same automated workflow:

1. Command Center:
   - SMS queue health;
   - parser health;
   - transaction totals;
   - allocation status;
   - recent activity;
   - exception count.
2. SMS Intake:
   - raw SMS metadata;
   - parse status;
   - sender;
   - timestamp;
   - safe redacted evidence;
   - protected raw SMS reveal only for authorized audited admins.
3. Transactions:
   - parsed transaction rows;
   - amount;
   - network;
   - direction;
   - reference;
   - confidence;
   - linked payment intent;
   - allocation status.
4. Groups:
   - groups;
   - group owners;
   - receiver MoMo status;
   - member count;
   - SMS automation status.
5. Members:
   - Collect ID;
   - masked MoMo/phone tail;
   - group membership;
   - contribution totals.
6. Review:
   - low-confidence parser outputs;
   - unmatched/ambiguous allocation cases;
   - duplicate/replay issues;
   - operational exceptions.
7. Settings:
   - admin users;
   - SMS sender IDs;
   - parser configuration;
   - platform health;
   - audit/security controls.

Admin must not present fake metrics, demo operational content, or manual user fallback flows.

## Required Feature Set

### Mobile App

- WhatsApp OTP login for any supported phone number.
- Auto-generated 6-digit Collect ID.
- Profile with MoMo number.
- Three-tab navigation: Home, Groups, Settings.
- Groups list and group detail.
- Android-only group creation.
- iOS group creation inactive with the exact message `group creation is available only on Android`.
- First Android group creation triggers SMS access consent/permission.
- Simplified group creation:
  - group name;
  - optional description;
  - receiver MoMo number prefilled from profile;
  - editable receiver MoMo number.
- Share group by link, QR code, deep link, chat apps, SMS, and native share sheet.
- Join group.
- Contribute amount.
- Create Supabase payment intent linked to member 6-digit Collect ID when member taps `Contribute`.
- Launch MoMo USSD through `tel:`.
- Show contribution status from Supabase realtime payment-intent/allocation updates, not from user-entered confirmation.
- No manual SMS paste.
- No reported transaction ID field.
- No anonymity picker.
- No display-name/real-name field.
- No category/target/cover/public-directory campaign workflow in the default product.

### Android SMS Layer

- `RECEIVE_SMS` and `READ_SMS` permission flow for Android group owners.
- Official MoMo sender allowlist.
- BroadcastReceiver for live SMS.
- Inbox/backfill support where appropriate.
- Local durable queue.
- Canonical SMS hash.
- Batch upload with authenticated signed request.
- WorkManager retry/backoff.
- Device/gateway health state.

### Supabase Backend

- Raw SMS evidence table.
- Payment intent table linked to group, member, 6-digit Collect ID, receiver MoMo, amount, and status.
- Parsed transaction table.
- Transaction allocation table.
- Group/member ledger views.
- Parser outcome metrics.
- SMS sender/provider configuration.
- Edge Function for signed SMS ingestion/parsing.
- OpenAI API structured parser.
- Validation that blocks unsafe parser output.
- Idempotent transaction insert by SMS hash/device/user.
- Payment-intent-based allocation trigger or RPC.
- Exception queue for backend/admin review.
- Realtime invalidation for SMS, transactions, allocations, groups, members, and admin health.

### Admin PWA

- Dedicated admin entrypoint remains required.
- Admin panel must align to automated SMS pipeline:
  - Command Center;
  - SMS Intake;
  - Transactions;
  - Groups;
  - Members;
  - Review;
  - Settings.
- Raw SMS reveal remains restricted and audited.
- Admin can monitor and resolve exceptions.
- Admin can view parser/allocation health.
- Admin must not be a substitute for user-side manual confirmation.

## UI/UX Rules

- Use `Groups`, not `Goals`.
- Bottom nav: Home, Groups, Settings only.
- Keep contribution flow short: amount -> Contribute -> MoMo USSD dialer.
- Keep group creation short: group name, optional description, synced receiver MoMo, optional receiver edit.
- Keep group sharing simple: link, QR code, native share sheet, chat apps, and SMS.
- Keep profile as the only place for MoMo number management.
- Use Collect ID everywhere identity is needed.
- Avoid asking for or showing real names.
- Avoid repeated privacy/anonymity prompts.
- Avoid category, target, cover image, campaign storytelling, or public directory unless explicitly approved later.
- iPhone create group button is inactive; tapping it shows exactly `group creation is available only on Android`.
- SMS access consent must be plain and specific: Collect reads MoMo SMS notifications to automate group contribution records.

## Decisions Still To Confirm Before Implementation

1. Exact USSD template per MoMo provider and whether amount/receiver can be prefilled reliably through `tel:`.
2. Whether the MoMo USSD reference field can include the member's 6-digit Collect ID or payment intent code on supported flows.
3. Whether groups support invite-only links, public share links, or both.
4. Final QR/deep-link URL format for group sharing.

## Implementation Direction After Approval

After this product definition is approved, the current Collect app should be refactored to remove incorrect flows and align to this model:

- Replace collections/goals language with groups.
- Replace current navigation with Home, Groups, Settings.
- Remove manual SMS paste and legacy SMS operator UI.
- Remove contribution anonymity and reported transaction ID fields.
- Remove Rwanda-only login normalization if it blocks non-Rwanda WhatsApp numbers.
- Simplify profile and group creation.
- Add group link/QR/deep-link sharing.
- Add payment-intent creation before launching MoMo USSD contribution.
- Implement Android SMS access and queueing using PayLedger's gateway pattern.
- Implement Supabase raw SMS -> OpenAI parser -> transactions -> payment-intent-based allocations workflow using PayLedger's backend pattern adapted to Collect groups and 6-digit user IDs.
- Update Admin PWA to monitor SMS, payment intents, transactions, realtime allocations, groups, members, and exceptions.
