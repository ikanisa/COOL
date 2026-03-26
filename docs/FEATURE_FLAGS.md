# Feature Flags & Kill-Switches

> Managed via Firebase Remote Config + `EngagementFeatureFlags`.
> Last updated: March 2026

## Architecture

```
Firebase Remote Config
  ↓ (fetch + activate, 4h cache)
FeatureFlagsService.initialize()
  ↓ (merge defaults → remote → app-config overrides)
EngagementFeatureFlags (immutable snapshot)
  ↓ (consumed by providers + UI)
ManagedFeatureRollout.isEnabled(isAdmin:)
```

**Source**: [`feature_flags_service.dart`](../lib/core/services/feature_flags_service.dart)
**Model**: [`engagement_feature_flags.dart`](../lib/core/models/engagement_feature_flags.dart)

---

## Kill-Switches

Kill-switches **immediately disable** a feature for all users (including admins).

| Key | Feature | Owner | Default |
|-----|---------|-------|---------|
| `kill_momo_payments` | MoMo send/receive/QR/NFC | Platform | `false` |
| `kill_ticket_purchase` | Rayon Sport ticket buy | Platform | `false` |

### How to Activate a Kill-Switch

1. Open **Firebase Console** → Remote Config
2. Set the kill-switch key to `true`
3. **Publish** the change
4. Users get the new value on next app launch or within 4 hours

### Rollback

Set the key back to `false` and publish.

---

## Rollout Stages

Each managed feature has a `stage` controlling visibility:

| Stage | Behavior |
|-------|----------|
| `live` | Available to all users |
| `pilot` | Available to all users (used for metrics) |
| `internal` | Admin-only |
| `disabled` | Hidden from all users |

### Rollout Config Keys

| Feature | Stage Key | Admin-Only Key |
|---------|-----------|----------------|
| MoMo | `feature_momo_stage` | `feature_momo_admin_only` |
| Tickets | `feature_ticket_purchase_stage` | `feature_ticket_purchase_admin_only` |

---

## Engagement Flags

| Key | Purpose | Default |
|-----|---------|---------|
| `engagement_enabled` | Master engagement system toggle | `true` |
| `engagement_share_tracking_enabled` | Track share events for XP | `true` |
| `engagement_group_captain_enabled` | Group captain badge system | `false` |
| `engagement_rayon_chapter_enabled` | Rayon Sport chapter system | `false` |

---

## Adding a New Feature Flag

1. Add the key to `EngagementFeatureFlags` model
2. Add default value in `.defaults()` factory
3. Add parsing in `.fromValues()` factory
4. Add Remote Config read in `_readRemoteConfigValues()`
5. Add Remote Config default in Firebase Console
6. Update this document
