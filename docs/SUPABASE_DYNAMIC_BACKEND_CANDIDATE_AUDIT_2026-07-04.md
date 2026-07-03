# Supabase Dynamic Backend Candidate Audit

Date: 2026-07-04
Repo: `/Volumes/PRO-G40/COOL`

## Purpose

This is the repo-wide candidate register for moving hardcoded business data,
operator workflow rules, public content, settings, and flexible product logic
into Supabase tables and RPCs. It is not a claim that every candidate has
already been migrated. It separates production candidates from code that should
remain in source control because it is security-sensitive, structural, test-only,
or part of the Flutter/router/runtime contract.

## Current Dynamic Baseline

The repo already has a substantial Supabase backend. The latest local validation
before this audit showed:

- `expected_objects=186`, `remote_objects=186`, `extra=0`, `missing=0`
- `tables=37`, `rls_enabled_tables=37`
- `functions=70`, `policies=69`
- `app_role_grants=304`
- zero Supabase performance advisor warnings

Existing dynamic primitives that should be reused instead of duplicated:

- `feature_flags` and `system_settings` tables with RLS, created in
  `supabase/migrations/202605230008_admin_panel.sql:43` and
  `supabase/migrations/202605230008_admin_panel.sql:54`.
- Admin RPCs for feature flags and settings at
  `supabase/migrations/202605230008_admin_panel.sql:512` and
  `supabase/migrations/202605230008_admin_panel.sql:528`.
- Initial flags and settings such as `payments.mode` and
  `sms.parser.schema_version` in
  `supabase/migrations/202605230013_admin_settings_flags.sql:1`.
- Realtime invalidation through `app_realtime_events`, including
  `feature_flags` and `settings`, in
  `supabase/migrations/202605250001_app_realtime_invalidation.sql:1` and
  `supabase/migrations/202605250001_app_realtime_invalidation.sql:87`.
- Notification tables and device/event RPCs in
  `supabase/migrations/20260608090000_native_notifications.sql:1`.
- Payment instruction templates in
  `supabase/migrations/202605230001_collect_baseline.sql:86`.
- Collection type/category fields and server-side validation in
  `supabase/migrations/20260622090000_market_expansion_categories_stripe_foundation.sql:5`.

## Candidate Rules

Move an item to Supabase when it is:

- Business-editable without an app release.
- User-facing or operator-facing copy, labels, reasons, options, or workflow
  thresholds.
- Duplicated across mobile, Admin PWA, public web, scripts, or Edge Functions.
- Likely to vary by country, partner, product, audience, language, or launch
  stage.
- Needed by both client and server, where a server RPC can enforce the rule.
- Auditable or permissioned, especially admin workflows and sensitive settings.

Keep an item in code when it is:

- A secret, SDK URL, OAuth scope, local storage key, router path contract, test
  fixture, release evidence artifact, or build-time environment boundary.
- A Flutter widget/icon/layout implementation detail.
- A security primitive that must not be editable through client-readable tables.
- Test, UAT, smoke, golden, or evidence-mode data.

## Candidate Matrix

| Priority | Candidate | Evidence | Current behavior | Supabase target |
| --- | --- | --- | --- | --- |
| P0 | Public website pages, FAQs, metrics, sections, SEO metadata, contact footer, regulatory notes | `scripts/public_static_site_build.rb:12`, `scripts/public_static_site_build.rb:52`, `scripts/public_static_site_build.rb:103`, `lib/features/landing/public_page_content.dart:3`, `lib/features/landing/public_policy_page_content.dart:3` | Public website content is mostly built from Ruby/Dart constants and YAML files, so content changes require repo changes and rebuilds. | Add `public_pages`, `public_page_revisions`, `public_page_sections`, `public_faqs`, `public_site_navigation`, `public_site_contact_channels`, `public_site_localizations`. Expose published data through `get_public_site_manifest(locale text)` and `get_public_page(path text, locale text)`. Admin writes require `settings.manage` or a new `content.manage` permission and audit logs. |
| P0 | Support contacts and public payment entry points | `lib/features/landing/collect_landing_page.dart:31`, `lib/shared/utils/support_contact.dart:5`, `scripts/public_static_site_build.rb:15` | WhatsApp, email, USSD, registered entity, and public URLs are duplicated across app and public build script. | Create `support_channels`, `payment_entrypoints`, `brand_entities`, and a client-safe `get_public_runtime_config()` RPC. Keep secrets in env; expose only published contact/payment metadata. |
| P0 | Admin list specs, status filters, sort filters, queue signals, workflow steps | `lib/admin/core/admin_list_specs.dart:20`, `lib/admin/core/admin_list_specs.dart:34`, `lib/admin/core/admin_list_specs.dart:270`, `lib/admin/core/admin_list_specs.dart:292` | Admin queues are hardcoded per RPC, even though the underlying data comes from Supabase. | Add `admin_queue_specs`, `admin_queue_status_filters`, `admin_queue_sort_options`, `admin_queue_workflow_steps`, `admin_queue_priority_signals`. Expose via `admin_runtime_config()` or extend `admin_list_*` responses to include metadata. RLS must require matching admin permissions. |
| P0 | Admin navigation visibility, labels, order, route-to-permission map | `lib/admin/admin_shell.dart:81` | Navigation labels/order are hardcoded in the Admin PWA. Permission checks exist, but presentation is not configurable. | Add `admin_navigation_items` with `route`, `label`, `icon_key`, `permission_name`, `display_order`, `enabled`. Fetch through `admin_runtime_config()`. Keep actual route definitions in Flutter code. |
| P1 | Feature flags and system settings client consumption | `supabase/migrations/202605230008_admin_panel.sql:43`, `supabase/migrations/202605230013_admin_settings_flags.sql:1`, `lib/app/env/app_env.dart:27` | Tables exist, but much of the app still relies on build-time env values. | Add `get_runtime_settings(scope text)` and client cache/realtime invalidation. Build-time env remains for Supabase URL/anon key, secret gates, and local release boundaries; product flags and non-sensitive runtime behavior should come from Supabase. |
| P1 | In-app legal/privacy/terms content and account deletion reasons | `lib/features/status/account_legal_screens.dart:142`, `lib/features/status/account_legal_screens.dart:170`, `lib/features/status/account_legal_screens.dart:270` | Legal text and account request reason choices ship in app source. | Add `policy_documents`, `policy_document_sections`, `policy_acceptance_events`, `account_request_reason_options`. Expose active policies via `get_active_policy_document(kind text, locale text)` and reasons via `list_account_request_reasons()`. |
| P1 | Collection type catalog, category subtypes, default subtypes, purpose labels | `lib/features/collections/collection_create_widgets.dart:76`, `lib/features/collections/group_profile_form_controls.dart:242`, `supabase/migrations/20260622090000_market_expansion_categories_stripe_foundation.sql:5` | Server validates top-level type, while default subtypes are duplicated in clients. | Add `collection_type_catalog`, `collection_category_subtypes`, `collection_purpose_templates`, `collection_type_country_rules`. Server RPCs must validate against active catalog rows. Clients should fetch active options and cache defaults. |
| P1 | Payment workflow labels, status labels, status tones, pipeline steps | `lib/shared/widgets/collect_financial_payment_pipeline.dart:11`, `lib/shared/widgets/collect_financial_payments.dart:266` | Payment status rendering and stage copy are hardcoded, while payment instructions already have a table. | Extend payment configuration with `payment_status_catalog`, `payment_workflow_stages`, `payment_status_transitions`, or add a typed JSON setting under `system_settings` if the workflow remains small. Critical transitions stay enforced in SQL/RPCs. |
| P1 | Notification channel copy, event type catalog, delivery templates | `lib/core/notifications/collect_notification_service.dart:36`, `supabase/migrations/20260608090000_native_notifications.sql:24` | Notification storage exists, but channel labels/descriptions and event copy are source constants or inserted at call time. | Add `notification_channels`, `notification_event_types`, `notification_templates`, `notification_template_versions`. `enqueue_notification_event` should accept a template key and context rather than arbitrary copy for most events. |
| P1 | Public/app URLs and brand/runtime identity | `lib/app/env/app_env.dart:5`, `scripts/public_static_site_build.rb:12`, `scripts/public_static_site_build.rb:19` | Some URLs and public entity metadata are build-script constants. | Use `brand_entities`, `public_runtime_settings`, and `deployment_targets`. Keep app bootstrap URLs in build env only when required to find Supabase or avoid circular dependency. |
| P1 | Play Integrity package/platform config | `supabase/functions/verify-play-integrity/index.ts:21`, `supabase/functions/verify-play-integrity/index.ts:172` | Package name is env-overridable, with a hardcoded fallback in the Edge Function. | Prefer a required env var or `mobile_app_integrations` table keyed by platform/package/environment. Service account JSON, OAuth scope, and token URL remain env/code, not DB-editable. |
| P2 | Realtime subscription area catalog | `lib/core/supabase/realtime_invalidation.dart:7`, `supabase/migrations/202605250001_app_realtime_invalidation.sql:1` | Area names are duplicated in client and database check constraints. | Keep client subscriptions in code for now. If modules expand, add `realtime_area_catalog` and generate or validate migrations/tests from it. |
| P2 | Mobile/settings menu labels and support destinations | `lib/features/settings/settings_screen.dart:27` | Settings tiles are hardcoded. | Only move visibility/order/copy to `mobile_navigation_items` or `settings_menu_items` after runtime config exists. Routes and widget composition stay in code. |
| P2 | Phone network/country expansion rules | `lib/core/security/phone_normalizer.dart:21`, `lib/core/security/phone_normalizer.dart:46` | Rwanda and MTN MoMo validation are code rules. | Keep current validators in code for safety. For expansion, add `country_phone_rules` and `payment_network_rules`, then server-side RPC validation must be authoritative. |
| P2 | Route QA, browser QA, release-gate thresholds | `scripts/supabase_dynamic_candidate_scan.sh`, existing `scripts/*qa*`, `docs/release/*` | QA scripts and release evidence encode fixed expectations. | Keep in repo config unless an operator dashboard is built. Do not place release evidence artifacts in production Supabase tables by default. |

## Explicit Non-Candidates

These should normally stay out of dynamic production tables:

- Supabase URL, anon key, service role keys, Stripe secrets, Play service account
  JSON, OAuth scopes, API token URLs, captcha secrets.
- Flutter route definitions and GoRouter path contracts. Supabase may control
  labels/visibility, but not whether the app can compile or route safely.
- `SharedPreferences` keys, local install token keys, cache keys, test-only fake
  data, fixture repositories, golden/evidence pages, UAT scripts, and browser
  smoke expectations.
- Brand color implementation tokens unless the product explicitly supports
  admin-managed theming.

## Recommended Implementation Regime

1. Create a `runtime_config` access layer in Flutter and Admin PWA that fetches
   a single Supabase RPC payload, caches it locally, and refreshes on the
   existing `settings` / `feature_flags` realtime events.
2. Add a first migration for public runtime config:
   `support_channels`, `payment_entrypoints`, `brand_entities`, and
   `get_public_runtime_config()`. This removes the highest-risk duplicate phone,
   email, USSD, and public URL constants.
3. Add public content CMS tables and `get_public_site_manifest()` only after the
   app-level runtime config is stable. Public content needs revisioning,
   publishing status, locale support, author/reviewer columns, and audit logs.
4. Add Admin runtime metadata tables for queue specs and navigation. Keep RPC
   data access as-is, but return UI metadata from Supabase so queue labels,
   filters, sort options, and workflow instructions can change without a PWA
   release.
5. Add policy/legal document tables and account request reason options. These
   should be versioned and support explicit acceptance/deletion-request records.
6. Move category subtypes and payment status metadata last. Server RPCs must
   validate active catalog rows before clients rely on dynamic choices.
7. For every new table:
   - Enable RLS immediately.
   - Expose anonymous/public data through narrow views or stable RPCs only.
   - Use admin permissions for writes.
   - Record updates in `audit_logs` with a required reason.
   - Add indexes for published lookup keys and admin listing filters.
   - Add realtime invalidation only where clients need live refresh.

## Repeatable Scan

Run this command after new product work to catch fresh candidates:

```bash
bash scripts/supabase_dynamic_candidate_scan.sh
```

The scan is intentionally broad. A match is not automatically a migration task;
it is a review queue item to classify against the candidate rules above.

## Verification Used For This Audit

- Reviewed Supabase migrations, Edge Functions, app runtime env, Admin PWA
  specs, public website builders/content, legal screens, payment/status widgets,
  notification service, and collection category controls.
- Ran the linked Supabase inventory and readiness checks before this audit; the
  database object inventory was complete and Supabase performance advisor
  warnings were zero.
- Added the repeatable scan script above to make the candidate regime
  reproducible.
