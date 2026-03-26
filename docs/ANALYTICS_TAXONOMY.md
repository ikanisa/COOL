# Analytics Taxonomy

> Event naming conventions, user properties, key events, and funnels.
> Source of truth: `lib/core/models/engagement_event.dart` + `lib/core/services/engagement_tracker.dart`
> Last updated: March 2026

## Naming Conventions

- **Events**: `snake_case`, max 40 chars, prefix by domain when ambiguous
- **Parameters**: `snake_case`, max 40 chars for key, max 100 chars for string values
- **User Properties**: `snake_case`, max 24 chars for key

## Events

### Core Lifecycle

| Event | Parameters | Trigger |
|---|---|---|
| `app_opened` | — | App cold start |
| `session_started` | `user_id`, `authenticated`, `profile_complete`, `source` | After auth check completes |

### Deep Links & Invites

| Event | Parameters | Trigger |
|---|---|---|
| `deep_link_opened` | `scheme`, `host`, `path`, `route`, `has_query`, `campaign`, `referral_invite_id` | Deep link resolved |
| `invite_sent` | `channel`, `invite_url`, `target_type` | User shares an invite |
| `invite_opened` | `invite_code`, `campaign`, `referral_invite_id` | Invite link opened |
| `invite_accepted` | `invite_code`, `group_id`, `campaign`, `referral_invite_id` | User joins via invite |

### Engagement & Features

| Event | Parameters | Trigger |
|---|---|---|
| `share_action` | `channel`, `target_type`, `target_url` | User shares content (gated by `shareTrackingEnabled` flag) |
| `discover_tab_switch` | `from_tab`, `to_tab` | User switches discover tab |
| `wallet_add_started` | — | User initiates wallet add |
| `wallet_add_completed` | — | Wallet add succeeds |

## User Properties

Set via `identifyUser()` in `EngagementTracker`:

| Property | Source | Example |
|---|---|---|
| `market` | `AppMarket.countryCode` | `RW` |
| `ui_language` | `AppMarket.languageCode` | `en` |
| `momo_provider` | User profile | `mtn_rwanda` |

## Key Funnels

### MoMo Send Funnel
```
wallet_add_started → (recipient selected) → (amount entered) → wallet_add_completed
```

### Invite Conversion Funnel
```
invite_sent → invite_opened → invite_accepted
```

## Parameter Value Rules

1. **Booleans** → logged as `1` (true) or `0` (false) for BigQuery compatibility
2. **Strings** → trimmed, max 100 chars (truncated if longer)
3. **Null values** → omitted from analytics payload (not sent as empty strings)
4. **URIs** → converted to string via `.toString()`

## Feature Flags Affecting Analytics

| Flag | Effect |
|---|---|
| `engagement_enabled` | Master switch — disables all analytics collection |
| `engagement_share_tracking_enabled` | Gates `share_action` events |

## Firebase Console Setup

- **Custom definitions**: Register all user properties above in Firebase Console → Custom Definitions
- **Audiences**: Create audiences by `momo_provider`
- **Remote Config targeting**: Use `momo_provider` user properties for flag overrides
