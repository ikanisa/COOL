# Database

The baseline schema starts at
`supabase/migrations/202605230001_collect_baseline.sql`. The current SMS-first
Groups contract is added by
`supabase/migrations/202605270001_sms_first_group_payment_intents.sql`.

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
- `parsed_payment_events`: OpenAI parser output and allocation status.
- `payments`, `payment_allocations`, `ledger_entries`: posted contributions,
  allocation evidence, and immutable ledger.
- `app_realtime_events`: invalidation stream for mobile/Admin refresh.

Product rules in the database:

- Contribution identity is always anonymous in product flows.
- `payment_intents.contributor_public_id` stores the member Collect ID used for
  SMS allocation.
- Contributors do not update payment intents with payment references.
- `allocate_parsed_payment_event` matches parsed MoMo SMS to pending payment
  intents by receiver, amount, time window, contribution code, and/or explicit
  6-digit Collect ID.
- Ambiguous or low-confidence results remain exceptions and are not posted to
  the ledger automatically.

Important RPCs:

- `get_current_profile`
- `create_group_with_owner`
- `join_group_by_slug`
- `create_payment_intent`
- `create_contribution_intent`
- `allocate_parsed_payment_event`
- `record_sms_access_consent`

Removed legacy public surface in the current migration:

- `report_payment_intent_paid`
- `manual_allocate_parsed_payment_event`
- `admin_manual_allocate_payment`
- Public group-request review RPCs and views.
- Payment instruction templates.
- Receiver-mode consent RPCs.

RLS is enabled on public tables. Flutter-visible reads go through scoped tables,
safe views, or security-definer RPCs. Service-only writes use Supabase Edge
Functions and service role on the server side only.
