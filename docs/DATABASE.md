# Database

The baseline migration is `supabase/migrations/202605230001_collect_baseline.sql`.

It creates:

- Profiles with stable unique 6-digit numeric public IDs.
- Private/public collection lifecycle tables.
- Optional profile avatar URLs and collection cover image URLs.
- Receiver MOMO tables with phone hash support.
- Configurable Rwanda-only payment instruction templates for MOMO/USSD copy.
- Invite, payment intent, raw SMS, parsed event, payment, allocation, and immutable ledger tables.
- Recurring periods and member obligations.
- Public listing requests, reports, receiver consents, OTP rate limits, and audit logs.

RLS is enabled on all public tables. Safe views are provided:

- `public_profiles_view`
- `public_collections_view`
- `public_contributions_view`
- `collection_summary_view`
- `member_collections_view`
- `member_collection_summary_view`
- `member_contributions_view`
- `member_public_collection_requests_view`

Money is stored as integer RWF. Collection totals are derived through views over ledger entries.

The base `profiles` table is not broadly selectable by app roles. Public and
member-facing screens use safe views for aliases and avatars, while the signed
in user reads their own full profile through `get_current_profile()`.

Public contribution feeds must use `public_contributions_view`. Authenticated
collection screens use `member_collections_view`, `member_contributions_view`,
and `member_public_collection_requests_view` instead of reading private base
tables directly. `member_collections_view` only exposes receiver MOMO numbers to
collection admins or configured receivers; normal public browsing still gets the
receiver number only after a payment intent is created.

`collection_summary_view` is public-safe and only summarizes
`public_approved` non-archived collections. Private/member collection summaries
come from `member_collection_summary_view`, which scopes rows through
`user_can_read_collection`.

Contributors report “I have paid” through `report_payment_intent_paid`; app
roles do not have broad direct update privileges on `payment_intents`. Server
allocation functions are responsible for moving intents to `matched`.
Payment posting rejects cross-collection payment intents and only posts parsed
events to collections where the event receiver is configured as an active
collection receiver.
Raw SMS and parsed payment events persist an optional `collection_id` when the
receiver flow supplies one. Review screens read
`parsed_payment_events_review_view`, which scopes ambiguous/unallocated events
to collections through that explicit collection id or through the receiver MOMO
hash.

Function execution is explicitly scoped: the migration revokes default
`PUBLIC` execute privileges on public-schema functions, grants helper/app RPCs
only to the intended app roles, and grants service-only functions to
`service_role`. Migration `202605230007_revoke_public_function_execute.sql`
also revokes PostgreSQL `PUBLIC` execution from all current and future
public-schema functions, then restores only the intended `anon`,
`authenticated`, and `service_role` grants.

Important RPCs:

- `create_collection_with_owner`
- `get_current_profile`
- `create_collection_invite`
- `create_payment_intent_with_instructions`
- `create_payment_intent`
- `report_payment_intent_paid`
- `request_public_collection`
- `review_public_collection`
- `allocate_parsed_payment_event`
- `manual_allocate_parsed_payment_event`
- `record_receiver_mode_consent`

Admin RPCs are prefixed with `admin_`. They authorize with
`assert_admin_permission`, return redacted JSON payloads to the Flutter admin
panel, and write audit records for sensitive or high-risk actions.

Admin RBAC, feature flags, settings, moderation notes, sensitive access logs,
and admin audit records are part of the current production schema. Any stale
admin helper RPC that is not in the local migration contract is removed by a
forward-only cleanup migration.

Raw SMS body is not granted for direct authenticated table reads. Admin users
receive masked metadata through `admin_list_sms_metadata` and
`admin_get_sms_metadata`; raw body access is only through
`admin_reveal_raw_sms` with permission and reason.

`create_collection_with_owner` accepts optional `cover_image_url`, recurring
flags, and recurring rule JSON. When `is_recurring` is true, it creates the
first open recurring period so member obligation tracking has a concrete period
anchor.

`create_collection_invite` returns the one-time private invite token but stores
only its SHA-256 hash. Invites can target a hashed phone number or a 6-digit
Collect public ID, and owner role cannot be granted by invite.

`create_payment_intent_with_instructions` returns receiver MOMO details only
after the intent is created. Its instruction copy is rendered from active
`payment_instruction_templates`, so USSD text can be changed without a Flutter
release.
