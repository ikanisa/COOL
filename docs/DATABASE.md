# Database

The baseline schema starts at
`supabase/migrations/202605230001_collect_baseline.sql`. The current reviewed
SMS-first Groups contract is the complete ordered ledger ending at
`supabase/migrations/20260815085000_atomic_provider_finality_gateway.sql`.

Core data model:

- `profiles`: user account, WhatsApp phone, stable 6-digit `public_id`, profile
  MoMo number.
- `collections`: product-level Groups. Existing table name remains
  `collections`; UI copy uses Groups.
- `collection_members`: group roles and membership.
- `collection_receivers`: active receiver MoMo numbers and hashes.
- `payment_intents`: pending expected contributions linked to group, amount,
  receiver hash, contributor user id, and contributor 6-digit Collect ID.
- `raw_payment_sms`: MoMo SMS rows uploaded from Android SMS access.
- `parsed_payment_events`: OpenAI parser output and allocation status. Current
  parser output does not store payer/receiver names or raw payment reason text.
- `payments`, `payment_allocations`: provider-awaiting candidates, posted
  contributions, and their allocation evidence.
- `payment_provider_confirmations`, `provider_finality_requests`: service-only
  provider evidence and replay-safe signed-delivery audit state.
- `ledger_entries`: immutable collection/member credits created only by a
  matching provider confirmation.
- `app_realtime_events`: invalidation stream for mobile/Admin refresh.

Product rules in the database:

- Contribution identity uses generated 6-digit Collect IDs only; product flows
  do not ask for real names or anonymity choices.
- `payment_intents.contributor_public_id` stores the member Collect ID used for
  SMS allocation.
- Contributors do not update payment intents with payment references.
- `allocate_parsed_payment_event` matches parsed MoMo SMS to pending payment
  intents by receiver, amount, time window, and explicit 6-digit Collect ID.
  It creates no balance-bearing ledger entries and does not allocate from
  member-entered references or contribution codes.
- `process_provider_finality_event` is service-role-only, registers exact-body
  replay state transactionally, and delegates to matching confirmation or
  rejection logic.
- Ambiguous or low-confidence results remain exceptions and are not posted to
  the ledger automatically.

Important RPCs:

- `get_current_profile`
- `mint_native_action_capability`
- `create_group_with_owner_attested`
- `get_group_share_code`
- `rotate_group_share_code`
- `join_group_by_share_code`
- `update_collection_profile_and_receiver`
- `create_contribution_intent`
- `ingest_raw_payment_sms`
- `claim_raw_payment_sms_for_parse`
- `allocate_parsed_payment_event`
- `process_provider_finality_event`
- `confirm_provider_payment`
- `reject_provider_payment`

Removed legacy public surface in the current migration:

- `report_payment_intent_paid`
- `manual_allocate_parsed_payment_event`
- `admin_manual_allocate_payment`
- Public group-request review RPCs and views.
- Payment instruction templates.
- Caller-asserted receiver consent as authorization for Android-only creation.

RLS is enabled on public tables. Flutter-visible reads go through scoped tables,
safe views, or security-definer RPCs. Service-only writes use Supabase Edge
Functions and service role on the server side only.
