# Permissions

> Every permission declared in `AndroidManifest.xml`, why it exists, when it is prompted, and what happens if denied.
> Last updated: March 2026

## Permission Matrix

| Permission | Why | When Prompted | Fallback if Denied |
|---|---|---|---|
| `INTERNET` | Core networking (Supabase, Firebase, APIs) | Never (normal permission) | App cannot function; show offline error |
| `POST_NOTIFICATIONS` | Push notifications (order updates, ride alerts, group invites) | On first FCM-triggered notification (Android 13+) | Notifications silently dropped; in-app alerts still work |
| `READ_SMS` | Android-only M-Money payment confirmation verification from approved sender IDs | When the user enables SMS access for Mobile Money verification on Android | Automatic payment verification is unavailable; payment-linked records may remain pending until later reconciliation |
| `RECEIVE_SMS` | Android-only background receipt of approved M-Money confirmation SMS | Same flow as `READ_SMS`; required for incoming confirmation capture on Android | Automatic payment verification is unavailable; payment-linked records may remain pending until later reconciliation |
| `ACCESS_FINE_LOCATION` | Mobility maps, nearby drivers, trip discovery | When user enters mobility tab or schedules a trip | Mobility features disabled; show permission rationale dialog |
| `ACCESS_COARSE_LOCATION` | Fallback location for city-level features | Same as FINE_LOCATION (requested together) | Same as FINE_LOCATION |
| `NFC` | MoMo tap-to-pay (NFC tag read) | When user taps "NFC Pay" button | NFC option hidden; USSD fallback available |
| `READ_CONTACTS` | Invite group members, share via contacts | When user opens contact picker in group invite flow | Contact picker unavailable; manual phone entry available |
| `CAMERA` | QR code scanning plus BioPay face enrollment and payee matching | When user opens QR scanner or BioPay face capture | QR scanner and BioPay capture disabled; manual entry and non-BioPay flows remain available |

## Hardware Features

| Feature | Required | Notes |
|---|---|---|
| `android.hardware.nfc` | `false` | App works without NFC; USSD is the primary MoMo flow |
| `android.hardware.camera` | `false` | Camera is optional; manual code entry is always available |
| `android.hardware.camera.autofocus` | `false` | Enhances QR scanning but not required |

## Permission Request Strategy

### Principles
1. **Never prompt on first launch** — wait until the feature is actually needed
2. **Show rationale first** — explain why the permission is needed before the system dialog
3. **Degrade gracefully** — every permission-gated feature has a non-permission fallback
4. **Respect "Don't ask again"** — guide user to Settings if permanently denied

### Request Flow
```
User triggers feature → Check permission status
  → Granted: proceed
  → Not determined: show rationale dialog → request permission
  → Denied (can ask again): show rationale dialog → request permission
  → Permanently denied: show "Go to Settings" dialog
```

## Google Play Data Safety

| Permission | Data Type | Purpose | Shared | Retained |
|---|---|---|---|---|
| Location | Approximate + Precise | App functionality (mobility) | No | Until account deletion |
| Contacts | Contact info | App functionality (invites) | No | Not stored server-side |
| Camera | Photos/Videos | App functionality (QR scan, BioPay face capture) | No | QR frames are not stored as gallery media; if the user enrolls in BioPay, Cool stores a derived biometric template plus consent and payout-route metadata |
| Notifications | — | App functionality | No | — |
| SMS | Messages | App functionality (approved Mobile Money payment verification on Android) | No | Matching sender messages are retained for payment reconciliation until account deletion or cleanup policy |
