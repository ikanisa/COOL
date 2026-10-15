-- Fresh Collect operational foundation. No recovered data or example rows.
-- Requires 0001_admin_accounts.sql. This migration adds storage invariants, not
-- API authorization, member authentication, provider verification or dispatch.
-- All money is exact integer RWF (zero decimal places), bounded to JavaScript's
-- maximum safe integer. Timestamps are integer UTC epoch seconds.
-- Keep trigger CASE expressions parenthesized: D1's remote SQL splitter can
-- mistake an unparenthesized CASE END for the trigger END (workers-sdk #4727).
PRAGMA foreign_keys = ON;

CREATE TABLE collect_users (
  id TEXT PRIMARY KEY NOT NULL CHECK(length(id)=36 AND substr(id,9,1)='-' AND substr(id,14,1)='-' AND substr(id,19,1)='-' AND substr(id,24,1)='-' AND length(replace(id,'-',''))=32 AND replace(id,'-','') NOT GLOB '*[^a-f0-9]*'),
  email TEXT UNIQUE COLLATE NOCASE,
  phone_e164 TEXT UNIQUE,
  status TEXT NOT NULL DEFAULT 'invited' CHECK(status IN ('invited','active','suspended','closed')),
  created_by_admin_id TEXT REFERENCES admin_users(id) ON DELETE RESTRICT,
  created_at INTEGER NOT NULL CHECK(created_at > 0),
  updated_at INTEGER NOT NULL CHECK(updated_at >= created_at),
  CHECK(email IS NULL OR (length(email) BETWEEN 3 AND 254 AND email=lower(trim(email)) AND instr(email,'@')>1)),
  CHECK(phone_e164 IS NULL OR (length(phone_e164)=13 AND substr(phone_e164,1,5)='+2507' AND substr(phone_e164,6,1) IN ('2','3','8','9') AND substr(phone_e164,2) NOT GLOB '*[^0-9]*')),
  CHECK(email IS NOT NULL OR phone_e164 IS NOT NULL)
) STRICT;

CREATE TABLE collect_profiles (
  user_id TEXT PRIMARY KEY NOT NULL REFERENCES collect_users(id) ON DELETE RESTRICT,
  public_id TEXT NOT NULL UNIQUE CHECK(length(public_id)=6 AND public_id NOT GLOB '*[^0-9]*'),
  display_name TEXT NOT NULL CHECK(length(trim(display_name)) BETWEEN 2 AND 120),
  country_code TEXT NOT NULL DEFAULT 'RW' CHECK(country_code='RW'),
  currency TEXT NOT NULL DEFAULT 'RWF' CHECK(currency='RWF'),
  created_at INTEGER NOT NULL CHECK(created_at > 0),
  updated_at INTEGER NOT NULL CHECK(updated_at >= created_at)
) STRICT;

CREATE TABLE collect_groups (
  id TEXT PRIMARY KEY NOT NULL CHECK(length(id)=36 AND substr(id,9,1)='-' AND substr(id,14,1)='-' AND substr(id,19,1)='-' AND substr(id,24,1)='-' AND length(replace(id,'-',''))=32 AND replace(id,'-','') NOT GLOB '*[^a-f0-9]*'),
  slug TEXT NOT NULL UNIQUE CHECK(length(slug) BETWEEN 3 AND 100 AND slug NOT GLOB '*[^a-z0-9-]*'),
  title TEXT NOT NULL CHECK(length(trim(title)) BETWEEN 3 AND 160),
  description TEXT NOT NULL DEFAULT '' CHECK(length(description)<=1000),
  collection_type TEXT NOT NULL CHECK(collection_type IN ('ikimina','sport','church','wedding','other')),
  category_subtype TEXT,
  purpose_label TEXT,
  country_code TEXT NOT NULL DEFAULT 'RW' CHECK(country_code='RW'),
  currency TEXT NOT NULL DEFAULT 'RWF' CHECK(currency='RWF'),
  status TEXT NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','active','suspended','archived')),
  visibility TEXT NOT NULL DEFAULT 'private' CHECK(visibility IN ('private','public_approved')),
  is_platform_sponsored INTEGER NOT NULL DEFAULT 0 CHECK(is_platform_sponsored IN (0,1)),
  recurring_cadence TEXT CHECK(recurring_cadence IN ('weekly','monthly','quarterly','annually')),
  suggested_amount_rwf INTEGER CHECK(suggested_amount_rwf BETWEEN 1 AND 9007199254740991),
  creator_user_id TEXT REFERENCES collect_users(id) ON DELETE RESTRICT,
  created_by_admin_id TEXT REFERENCES admin_users(id) ON DELETE RESTRICT,
  created_at INTEGER NOT NULL CHECK(created_at>0),
  updated_at INTEGER NOT NULL CHECK(updated_at>=created_at),
  CHECK(creator_user_id IS NOT NULL OR created_by_admin_id IS NOT NULL)
) STRICT;

CREATE TABLE collect_memberships (
  group_id TEXT NOT NULL REFERENCES collect_groups(id) ON DELETE RESTRICT,
  user_id TEXT NOT NULL REFERENCES collect_users(id) ON DELETE RESTRICT,
  role TEXT NOT NULL CHECK(role IN ('owner','admin','receiver','member','contributor','viewer')),
  status TEXT NOT NULL CHECK(status IN ('active','invited','removed','left')),
  joined_at INTEGER CHECK(joined_at>0),
  created_at INTEGER NOT NULL CHECK(created_at>0),
  updated_at INTEGER NOT NULL CHECK(updated_at>=created_at),
  PRIMARY KEY(group_id,user_id),
  CHECK(status!='active' OR joined_at IS NOT NULL)
) STRICT;
CREATE UNIQUE INDEX collect_memberships_active_owner ON collect_memberships(group_id) WHERE role='owner' AND status='active';
CREATE INDEX collect_memberships_user ON collect_memberships(user_id,status,group_id);

CREATE TABLE collect_payees (
  id TEXT PRIMARY KEY NOT NULL CHECK(length(id)=36 AND substr(id,9,1)='-' AND substr(id,14,1)='-' AND substr(id,19,1)='-' AND substr(id,24,1)='-' AND length(replace(id,'-',''))=32 AND replace(id,'-','') NOT GLOB '*[^a-f0-9]*'),
  group_id TEXT NOT NULL REFERENCES collect_groups(id) ON DELETE RESTRICT,
  label TEXT NOT NULL CHECK(length(trim(label)) BETWEEN 2 AND 120),
  network TEXT NOT NULL CHECK(network IN ('mtn_momo','airtel_money')),
  momo_number_or_code TEXT NOT NULL CHECK(length(momo_number_or_code) BETWEEN 4 AND 12 AND momo_number_or_code NOT GLOB '*[^0-9]*'),
  rail TEXT NOT NULL DEFAULT 'rwanda_momo' CHECK(rail='rwanda_momo'),
  currency TEXT NOT NULL DEFAULT 'RWF' CHECK(currency='RWF'),
  status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active','inactive')),
  created_by_admin_id TEXT NOT NULL REFERENCES admin_users(id) ON DELETE RESTRICT,
  creation_reason TEXT NOT NULL CHECK(length(trim(creation_reason)) BETWEEN 8 AND 1000),
  created_at INTEGER NOT NULL CHECK(created_at>0),
  UNIQUE(id,group_id,network),
  UNIQUE(id,group_id),
  UNIQUE(id,network)
) STRICT;
CREATE UNIQUE INDEX collect_payees_active_group ON collect_payees(group_id) WHERE status='active';
CREATE TRIGGER collect_payee_route_immutable BEFORE UPDATE ON collect_payees
WHEN NEW.id IS NOT OLD.id OR NEW.group_id IS NOT OLD.group_id OR NEW.network IS NOT OLD.network
  OR NEW.momo_number_or_code IS NOT OLD.momo_number_or_code OR NEW.rail IS NOT OLD.rail OR NEW.currency IS NOT OLD.currency
  OR NEW.created_by_admin_id IS NOT OLD.created_by_admin_id OR NEW.creation_reason IS NOT OLD.creation_reason OR NEW.created_at IS NOT OLD.created_at
BEGIN SELECT RAISE(ABORT,'MoMo payee route and creation evidence are immutable'); END;
CREATE TRIGGER collect_payee_no_delete BEFORE DELETE ON collect_payees
BEGIN SELECT RAISE(ABORT,'Deactivate the payee; do not erase its route'); END;

CREATE TABLE collect_operation_requests (
  id TEXT PRIMARY KEY NOT NULL CHECK(length(id)=36 AND substr(id,9,1)='-' AND substr(id,14,1)='-' AND substr(id,19,1)='-' AND substr(id,24,1)='-' AND length(replace(id,'-',''))=32 AND replace(id,'-','') NOT GLOB '*[^a-f0-9]*'),
  actor_admin_id TEXT NOT NULL REFERENCES admin_users(id) ON DELETE RESTRICT,
  scope TEXT NOT NULL CHECK(length(scope) BETWEEN 3 AND 100),
  idempotency_key TEXT NOT NULL CHECK(length(idempotency_key) BETWEEN 8 AND 200),
  request_sha256 TEXT NOT NULL CHECK(length(request_sha256)=64 AND request_sha256 NOT GLOB '*[^a-f0-9]*'),
  status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','succeeded','failed')),
  response_json TEXT CHECK(response_json IS NULL OR json_valid(response_json)),
  created_at INTEGER NOT NULL CHECK(created_at>0),
  completed_at INTEGER,
  UNIQUE(actor_admin_id,scope,idempotency_key),
  CHECK((status='pending' AND completed_at IS NULL AND response_json IS NULL)
    OR (status IN ('succeeded','failed') AND completed_at IS NOT NULL AND completed_at>=created_at AND response_json IS NOT NULL))
) STRICT;
CREATE TRIGGER collect_operation_request_identity BEFORE UPDATE ON collect_operation_requests
WHEN OLD.status!='pending' OR NEW.id IS NOT OLD.id OR NEW.actor_admin_id IS NOT OLD.actor_admin_id
  OR NEW.scope IS NOT OLD.scope OR NEW.idempotency_key IS NOT OLD.idempotency_key
  OR NEW.request_sha256 IS NOT OLD.request_sha256 OR NEW.created_at IS NOT OLD.created_at
BEGIN SELECT RAISE(ABORT,'Operation request identity and terminal result are immutable'); END;
CREATE TRIGGER collect_operation_request_no_delete BEFORE DELETE ON collect_operation_requests
BEGIN SELECT RAISE(ABORT,'Operation replay evidence cannot be deleted'); END;

CREATE TABLE collect_transactions (
  id TEXT PRIMARY KEY NOT NULL CHECK(length(id)=36 AND substr(id,9,1)='-' AND substr(id,14,1)='-' AND substr(id,19,1)='-' AND substr(id,24,1)='-' AND length(replace(id,'-',''))=32 AND replace(id,'-','') NOT GLOB '*[^a-f0-9]*'),
  group_id TEXT NOT NULL REFERENCES collect_groups(id) ON DELETE RESTRICT,
  payee_id TEXT NOT NULL,
  network TEXT NOT NULL CHECK(network IN ('mtn_momo','airtel_money')),
  provider_reference TEXT NOT NULL CHECK(length(trim(provider_reference)) BETWEEN 1 AND 160),
  rail TEXT NOT NULL DEFAULT 'rwanda_momo' CHECK(rail='rwanda_momo'),
  currency TEXT NOT NULL DEFAULT 'RWF' CHECK(currency='RWF'),
  amount_rwf INTEGER NOT NULL CHECK(amount_rwf BETWEEN 1 AND 9007199254740991),
  sender_phone_sha256 TEXT CHECK(sender_phone_sha256 IS NULL OR (length(sender_phone_sha256)=64 AND sender_phone_sha256 NOT GLOB '*[^a-f0-9]*')),
  verification_status TEXT NOT NULL DEFAULT 'pending' CHECK(verification_status IN ('pending','confirmation_recorded','rejection_recorded','evidence_conflict')),
  verified_by_admin_id TEXT REFERENCES admin_users(id) ON DELETE RESTRICT,
  verified_at INTEGER,
  observed_at INTEGER NOT NULL CHECK(observed_at>0),
  created_at INTEGER NOT NULL CHECK(created_at>0),
  UNIQUE(network,provider_reference),
  UNIQUE(id,group_id),
  UNIQUE(id,payee_id),
  FOREIGN KEY(payee_id,group_id,network) REFERENCES collect_payees(id,group_id,network) ON DELETE RESTRICT,
  CHECK((verification_status='pending' AND verified_at IS NULL AND verified_by_admin_id IS NULL)
    OR (verification_status!='pending' AND verified_at IS NOT NULL AND verified_at>=created_at AND verified_by_admin_id IS NOT NULL))
) STRICT;
CREATE INDEX collect_transactions_group ON collect_transactions(group_id,created_at,id);
CREATE TRIGGER collect_transaction_source_immutable BEFORE UPDATE ON collect_transactions
WHEN NEW.id IS NOT OLD.id OR NEW.group_id IS NOT OLD.group_id OR NEW.payee_id IS NOT OLD.payee_id
  OR NEW.network IS NOT OLD.network OR NEW.provider_reference IS NOT OLD.provider_reference OR NEW.rail IS NOT OLD.rail
  OR NEW.currency IS NOT OLD.currency OR NEW.amount_rwf IS NOT OLD.amount_rwf OR NEW.sender_phone_sha256 IS NOT OLD.sender_phone_sha256
  OR NEW.observed_at IS NOT OLD.observed_at OR NEW.created_at IS NOT OLD.created_at
BEGIN SELECT RAISE(ABORT,'Transaction source facts are immutable'); END;
CREATE TRIGGER collect_transaction_no_delete BEFORE DELETE ON collect_transactions
BEGIN SELECT RAISE(ABORT,'Transaction evidence cannot be deleted'); END;

CREATE TABLE collect_payment_allocations (
  id TEXT PRIMARY KEY NOT NULL CHECK(length(id)=36 AND substr(id,9,1)='-' AND substr(id,14,1)='-' AND substr(id,19,1)='-' AND substr(id,24,1)='-' AND length(replace(id,'-',''))=32 AND replace(id,'-','') NOT GLOB '*[^a-f0-9]*'),
  transaction_id TEXT NOT NULL,
  group_id TEXT NOT NULL,
  member_user_id TEXT,
  amount_rwf INTEGER NOT NULL CHECK(amount_rwf BETWEEN 1 AND 9007199254740991),
  operation_request_id TEXT NOT NULL UNIQUE REFERENCES collect_operation_requests(id) ON DELETE RESTRICT,
  created_by_admin_id TEXT NOT NULL REFERENCES admin_users(id) ON DELETE RESTRICT,
  created_at INTEGER NOT NULL CHECK(created_at>0),
  UNIQUE(id,group_id,transaction_id),
  FOREIGN KEY(transaction_id,group_id) REFERENCES collect_transactions(id,group_id) ON DELETE RESTRICT,
  FOREIGN KEY(group_id,member_user_id) REFERENCES collect_memberships(group_id,user_id) ON DELETE RESTRICT
) STRICT;
CREATE INDEX collect_allocations_transaction ON collect_payment_allocations(transaction_id);
CREATE TRIGGER collect_allocation_identity BEFORE UPDATE ON collect_payment_allocations
WHEN NEW.id IS NOT OLD.id OR NEW.transaction_id IS NOT OLD.transaction_id OR NEW.group_id IS NOT OLD.group_id
  OR NEW.operation_request_id IS NOT OLD.operation_request_id OR NEW.created_by_admin_id IS NOT OLD.created_by_admin_id OR NEW.created_at IS NOT OLD.created_at
BEGIN SELECT RAISE(ABORT,'Allocation identity and request evidence are immutable'); END;
CREATE TRIGGER collect_allocation_insert_bound BEFORE INSERT ON collect_payment_allocations
WHEN NEW.amount_rwf > (SELECT amount_rwf FROM collect_transactions WHERE id=NEW.transaction_id)
  - COALESCE((SELECT sum(amount_rwf) FROM collect_payment_allocations WHERE transaction_id=NEW.transaction_id),0)
BEGIN SELECT RAISE(ABORT,'Allocations exceed the transaction amount'); END;
CREATE TRIGGER collect_allocation_update_bound BEFORE UPDATE ON collect_payment_allocations
WHEN NEW.amount_rwf > (SELECT amount_rwf FROM collect_transactions WHERE id=NEW.transaction_id)
  - COALESCE((SELECT sum(amount_rwf) FROM collect_payment_allocations WHERE transaction_id=NEW.transaction_id AND id!=OLD.id),0)
BEGIN SELECT RAISE(ABORT,'Allocations exceed the transaction amount'); END;

CREATE TABLE collect_ledger_accounts (
  id TEXT PRIMARY KEY NOT NULL CHECK(length(id)=36 AND substr(id,9,1)='-' AND substr(id,14,1)='-' AND substr(id,19,1)='-' AND substr(id,24,1)='-' AND length(replace(id,'-',''))=32 AND replace(id,'-','') NOT GLOB '*[^a-f0-9]*'),
  group_id TEXT NOT NULL REFERENCES collect_groups(id) ON DELETE RESTRICT,
  code TEXT NOT NULL CHECK(length(code) BETWEEN 1 AND 40),
  name TEXT NOT NULL CHECK(length(trim(name)) BETWEEN 2 AND 120),
  account_type TEXT NOT NULL CHECK(account_type IN ('asset','liability','equity','income','expense')),
  normal_side TEXT NOT NULL CHECK(normal_side IN ('debit','credit')),
  currency TEXT NOT NULL DEFAULT 'RWF' CHECK(currency='RWF'),
  status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active','closed')),
  created_by_admin_id TEXT NOT NULL REFERENCES admin_users(id) ON DELETE RESTRICT,
  created_at INTEGER NOT NULL CHECK(created_at>0),
  UNIQUE(group_id,code),
  UNIQUE(id,group_id)
) STRICT;

CREATE TABLE collect_journals (
  id TEXT PRIMARY KEY NOT NULL CHECK(length(id)=36 AND substr(id,9,1)='-' AND substr(id,14,1)='-' AND substr(id,19,1)='-' AND substr(id,24,1)='-' AND length(replace(id,'-',''))=32 AND replace(id,'-','') NOT GLOB '*[^a-f0-9]*'),
  group_id TEXT NOT NULL REFERENCES collect_groups(id) ON DELETE RESTRICT,
  transaction_id TEXT,
  allocation_id TEXT UNIQUE,
  operation_request_id TEXT NOT NULL UNIQUE REFERENCES collect_operation_requests(id) ON DELETE RESTRICT,
  description TEXT NOT NULL CHECK(length(trim(description)) BETWEEN 3 AND 1000),
  currency TEXT NOT NULL DEFAULT 'RWF' CHECK(currency='RWF'),
  status TEXT NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','posted')),
  created_by_admin_id TEXT NOT NULL REFERENCES admin_users(id) ON DELETE RESTRICT,
  created_at INTEGER NOT NULL CHECK(created_at>0),
  posted_by_admin_id TEXT REFERENCES admin_users(id) ON DELETE RESTRICT,
  posted_at INTEGER,
  UNIQUE(id,group_id),
  FOREIGN KEY(transaction_id,group_id) REFERENCES collect_transactions(id,group_id) ON DELETE RESTRICT,
  FOREIGN KEY(allocation_id,group_id,transaction_id) REFERENCES collect_payment_allocations(id,group_id,transaction_id) ON DELETE RESTRICT,
  CHECK((transaction_id IS NULL AND allocation_id IS NULL) OR (transaction_id IS NOT NULL AND allocation_id IS NOT NULL)),
  CHECK((status='draft' AND posted_at IS NULL AND posted_by_admin_id IS NULL)
    OR (status='posted' AND posted_at IS NOT NULL AND posted_at>=created_at AND posted_by_admin_id IS NOT NULL))
) STRICT;
CREATE INDEX collect_journals_group ON collect_journals(group_id,status,created_at);
CREATE TRIGGER collect_journal_identity BEFORE UPDATE ON collect_journals
WHEN NEW.id IS NOT OLD.id OR NEW.group_id IS NOT OLD.group_id OR NEW.operation_request_id IS NOT OLD.operation_request_id
  OR NEW.created_by_admin_id IS NOT OLD.created_by_admin_id OR NEW.created_at IS NOT OLD.created_at
BEGIN SELECT RAISE(ABORT,'Journal identity and request evidence are immutable'); END;

CREATE TABLE collect_journal_entries (
  id TEXT PRIMARY KEY NOT NULL CHECK(length(id)=36 AND substr(id,9,1)='-' AND substr(id,14,1)='-' AND substr(id,19,1)='-' AND substr(id,24,1)='-' AND length(replace(id,'-',''))=32 AND replace(id,'-','') NOT GLOB '*[^a-f0-9]*'),
  journal_id TEXT NOT NULL,
  group_id TEXT NOT NULL,
  account_id TEXT NOT NULL,
  line_number INTEGER NOT NULL CHECK(line_number BETWEEN 1 AND 10000),
  debit_rwf INTEGER NOT NULL DEFAULT 0 CHECK(debit_rwf BETWEEN 0 AND 9007199254740991),
  credit_rwf INTEGER NOT NULL DEFAULT 0 CHECK(credit_rwf BETWEEN 0 AND 9007199254740991),
  description TEXT NOT NULL DEFAULT '' CHECK(length(description)<=500),
  UNIQUE(journal_id,line_number),
  FOREIGN KEY(journal_id,group_id) REFERENCES collect_journals(id,group_id) ON DELETE RESTRICT,
  FOREIGN KEY(account_id,group_id) REFERENCES collect_ledger_accounts(id,group_id) ON DELETE RESTRICT,
  CHECK((debit_rwf>0 AND credit_rwf=0) OR (credit_rwf>0 AND debit_rwf=0))
) STRICT;
CREATE INDEX collect_entries_account ON collect_journal_entries(account_id,journal_id);

CREATE TRIGGER collect_journal_insert_draft BEFORE INSERT ON collect_journals
WHEN NEW.status!='draft'
BEGIN SELECT RAISE(ABORT,'Create a draft, then validate and post it'); END;
CREATE TRIGGER collect_journal_posted_update BEFORE UPDATE ON collect_journals
WHEN OLD.status='posted'
BEGIN SELECT RAISE(ABORT,'Posted journals are immutable; use a new correcting journal'); END;
CREATE TRIGGER collect_journal_posted_delete BEFORE DELETE ON collect_journals
WHEN OLD.status='posted'
BEGIN SELECT RAISE(ABORT,'Posted journals cannot be deleted'); END;
CREATE TRIGGER collect_journal_post_balance BEFORE UPDATE OF status ON collect_journals
WHEN NEW.status='posted'
BEGIN
  SELECT (CASE WHEN (SELECT count(*) FROM collect_journal_entries WHERE journal_id=OLD.id)<2
    OR COALESCE((SELECT sum(debit_rwf)-sum(credit_rwf) FROM collect_journal_entries WHERE journal_id=OLD.id),1)!=0
    THEN RAISE(ABORT,'Posted journals require at least two balanced entries') END);
  SELECT (CASE WHEN EXISTS(SELECT 1 FROM collect_journal_entries e JOIN collect_ledger_accounts a ON a.id=e.account_id
    WHERE e.journal_id=OLD.id AND a.status!='active') THEN RAISE(ABORT,'Posting requires active ledger accounts') END);
  SELECT (CASE WHEN EXISTS(SELECT e.account_id FROM collect_journal_entries e WHERE e.journal_id=OLD.id GROUP BY e.account_id
    HAVING sum(e.debit_rwf)>9007199254740991-COALESCE((SELECT sum(p.debit_rwf) FROM collect_journal_entries p
      JOIN collect_journals j ON j.id=p.journal_id WHERE p.account_id=e.account_id AND j.status='posted'),0)
      OR sum(e.credit_rwf)>9007199254740991-COALESCE((SELECT sum(p.credit_rwf) FROM collect_journal_entries p
      JOIN collect_journals j ON j.id=p.journal_id WHERE p.account_id=e.account_id AND j.status='posted'),0))
    THEN RAISE(ABORT,'Posted account totals exceed exact integer range') END);
  SELECT (CASE WHEN NEW.allocation_id IS NOT NULL AND
    ((SELECT verification_status FROM collect_transactions WHERE id=NEW.transaction_id)!='confirmation_recorded'
      OR (SELECT amount_rwf FROM collect_payment_allocations WHERE id=NEW.allocation_id)
        != (SELECT sum(debit_rwf) FROM collect_journal_entries WHERE journal_id=OLD.id))
    THEN RAISE(ABORT,'Payment posting requires confirmed transaction and exact allocation amount') END);
END;

CREATE TRIGGER collect_entry_insert_guard BEFORE INSERT ON collect_journal_entries
BEGIN
  SELECT (CASE WHEN (SELECT status FROM collect_journals WHERE id=NEW.journal_id)!='draft'
    THEN RAISE(ABORT,'Posted journal entries are immutable') END);
  SELECT (CASE WHEN NEW.debit_rwf>9007199254740991-COALESCE((SELECT sum(debit_rwf) FROM collect_journal_entries WHERE journal_id=NEW.journal_id),0)
    OR NEW.credit_rwf>9007199254740991-COALESCE((SELECT sum(credit_rwf) FROM collect_journal_entries WHERE journal_id=NEW.journal_id),0)
    THEN RAISE(ABORT,'Journal totals exceed exact integer range') END);
END;
CREATE TRIGGER collect_entry_update_guard BEFORE UPDATE ON collect_journal_entries
BEGIN
  SELECT (CASE WHEN (SELECT status FROM collect_journals WHERE id=OLD.journal_id)!='draft'
    OR (SELECT status FROM collect_journals WHERE id=NEW.journal_id)!='draft'
    THEN RAISE(ABORT,'Posted journal entries are immutable') END);
  SELECT (CASE WHEN NEW.debit_rwf>9007199254740991-COALESCE((SELECT sum(debit_rwf) FROM collect_journal_entries WHERE journal_id=NEW.journal_id AND id!=OLD.id),0)
    OR NEW.credit_rwf>9007199254740991-COALESCE((SELECT sum(credit_rwf) FROM collect_journal_entries WHERE journal_id=NEW.journal_id AND id!=OLD.id),0)
    THEN RAISE(ABORT,'Journal totals exceed exact integer range') END);
END;
CREATE TRIGGER collect_entry_delete_guard BEFORE DELETE ON collect_journal_entries
WHEN (SELECT status FROM collect_journals WHERE id=OLD.journal_id)!='draft'
BEGIN SELECT RAISE(ABORT,'Posted journal entries are immutable'); END;

CREATE TRIGGER collect_allocation_posted_update BEFORE UPDATE ON collect_payment_allocations
WHEN EXISTS(SELECT 1 FROM collect_journals WHERE allocation_id=OLD.id AND status='posted')
BEGIN SELECT RAISE(ABORT,'Posted payment allocation is immutable'); END;
CREATE TRIGGER collect_allocation_posted_delete BEFORE DELETE ON collect_payment_allocations
WHEN EXISTS(SELECT 1 FROM collect_journals WHERE allocation_id=OLD.id AND status='posted')
BEGIN SELECT RAISE(ABORT,'Posted payment allocation cannot be deleted'); END;
CREATE TRIGGER collect_account_posted_identity BEFORE UPDATE ON collect_ledger_accounts
WHEN (NEW.id IS NOT OLD.id OR NEW.group_id IS NOT OLD.group_id OR NEW.code IS NOT OLD.code
  OR NEW.account_type IS NOT OLD.account_type OR NEW.normal_side IS NOT OLD.normal_side OR NEW.currency IS NOT OLD.currency)
  AND EXISTS(SELECT 1 FROM collect_journal_entries e JOIN collect_journals j ON j.id=e.journal_id WHERE e.account_id=OLD.id AND j.status='posted')
BEGIN SELECT RAISE(ABORT,'Posted ledger account identity is immutable'); END;

CREATE VIEW collect_posted_account_balances AS
SELECT a.id AS account_id,a.group_id,a.code,a.currency,
  COALESCE(sum(CASE WHEN j.status='posted' THEN e.debit_rwf ELSE 0 END),0) AS debits_rwf,
  COALESCE(sum(CASE WHEN j.status='posted' THEN e.credit_rwf ELSE 0 END),0) AS credits_rwf
FROM collect_ledger_accounts a LEFT JOIN collect_journal_entries e ON e.account_id=a.id
LEFT JOIN collect_journals j ON j.id=e.journal_id GROUP BY a.id,a.group_id,a.code,a.currency;

CREATE TABLE collect_receipt_ingress (
  id TEXT PRIMARY KEY NOT NULL CHECK(length(id)=36 AND substr(id,9,1)='-' AND substr(id,14,1)='-' AND substr(id,19,1)='-' AND substr(id,24,1)='-' AND length(replace(id,'-',''))=32 AND replace(id,'-','') NOT GLOB '*[^a-f0-9]*'),
  source_key TEXT NOT NULL CHECK(length(source_key) BETWEEN 1 AND 160),
  external_message_id TEXT NOT NULL CHECK(length(external_message_id) BETWEEN 1 AND 200),
  payee_id TEXT NOT NULL REFERENCES collect_payees(id) ON DELETE RESTRICT,
  payload_sha256 TEXT NOT NULL CHECK(length(payload_sha256)=64 AND payload_sha256 NOT GLOB '*[^a-f0-9]*'),
  payload_object_key TEXT NOT NULL CHECK(length(payload_object_key) BETWEEN 1 AND 500),
  received_at INTEGER NOT NULL CHECK(received_at>0),
  parse_status TEXT NOT NULL DEFAULT 'pending' CHECK(parse_status IN ('pending','parsed','parse_failed','needs_review')),
  parser_version TEXT,
  transaction_id TEXT,
  parsed_at INTEGER,
  UNIQUE(source_key,external_message_id),
  FOREIGN KEY(transaction_id,payee_id) REFERENCES collect_transactions(id,payee_id) ON DELETE RESTRICT,
  CHECK((parse_status='pending' AND parsed_at IS NULL AND parser_version IS NULL AND transaction_id IS NULL)
    OR (parse_status!='pending' AND parsed_at IS NOT NULL AND parsed_at>=received_at AND parser_version IS NOT NULL)),
  CHECK(parse_status!='parsed' OR transaction_id IS NOT NULL)
) STRICT;
CREATE INDEX collect_receipt_parse_queue ON collect_receipt_ingress(parse_status,received_at,id);
CREATE TRIGGER collect_receipt_source_immutable BEFORE UPDATE ON collect_receipt_ingress
WHEN NEW.id IS NOT OLD.id OR NEW.source_key IS NOT OLD.source_key OR NEW.external_message_id IS NOT OLD.external_message_id
  OR NEW.payee_id IS NOT OLD.payee_id OR NEW.payload_sha256 IS NOT OLD.payload_sha256
  OR NEW.payload_object_key IS NOT OLD.payload_object_key OR NEW.received_at IS NOT OLD.received_at
BEGIN SELECT RAISE(ABORT,'Receipt source evidence is immutable'); END;
CREATE TRIGGER collect_receipt_no_delete BEFORE DELETE ON collect_receipt_ingress
BEGIN SELECT RAISE(ABORT,'Receipt replay evidence cannot be deleted'); END;

CREATE TABLE collect_notification_outbox (
  id TEXT PRIMARY KEY NOT NULL CHECK(length(id)=36 AND substr(id,9,1)='-' AND substr(id,14,1)='-' AND substr(id,19,1)='-' AND substr(id,24,1)='-' AND length(replace(id,'-',''))=32 AND replace(id,'-','') NOT GLOB '*[^a-f0-9]*'),
  recipient_user_id TEXT NOT NULL REFERENCES collect_users(id) ON DELETE RESTRICT,
  group_id TEXT REFERENCES collect_groups(id) ON DELETE RESTRICT,
  transaction_id TEXT,
  channel TEXT NOT NULL CHECK(channel IN ('sms','email','push')),
  notification_type TEXT NOT NULL CHECK(length(notification_type) BETWEEN 3 AND 100),
  deduplication_key TEXT NOT NULL CHECK(length(deduplication_key) BETWEEN 8 AND 200),
  payload_json TEXT NOT NULL CHECK(json_valid(payload_json)),
  status TEXT NOT NULL DEFAULT 'queued' CHECK(status IN ('queued','leased','send_started','accepted','delivered','failed_no_send','uncertain','suppressed')),
  attempt_count INTEGER NOT NULL DEFAULT 0 CHECK(attempt_count BETWEEN 0 AND 1000),
  lease_token_sha256 TEXT CHECK(lease_token_sha256 IS NULL OR (length(lease_token_sha256)=64 AND lease_token_sha256 NOT GLOB '*[^a-f0-9]*')),
  lease_until INTEGER,
  provider_reference TEXT,
  outcome_evidence_key TEXT,
  created_at INTEGER NOT NULL CHECK(created_at>0),
  updated_at INTEGER NOT NULL CHECK(updated_at>=created_at),
  accepted_at INTEGER,
  delivered_at INTEGER,
  UNIQUE(recipient_user_id,channel,deduplication_key),
  FOREIGN KEY(transaction_id,group_id) REFERENCES collect_transactions(id,group_id) ON DELETE RESTRICT,
  CHECK(transaction_id IS NULL OR group_id IS NOT NULL),
  CHECK((status IN ('leased','send_started') AND lease_token_sha256 IS NOT NULL AND lease_until IS NOT NULL AND lease_until>created_at AND attempt_count>0)
    OR (status NOT IN ('leased','send_started') AND lease_token_sha256 IS NULL AND lease_until IS NULL)),
  CHECK(status NOT IN ('send_started','accepted','delivered','failed_no_send','uncertain') OR attempt_count>0),
  CHECK(status NOT IN ('accepted','delivered') OR (provider_reference IS NOT NULL AND length(provider_reference)>0 AND accepted_at IS NOT NULL AND accepted_at>=created_at)),
  CHECK(status!='delivered' OR (delivered_at IS NOT NULL AND delivered_at>=accepted_at)),
  CHECK(status NOT IN ('failed_no_send','uncertain') OR (outcome_evidence_key IS NOT NULL AND length(outcome_evidence_key)>0))
) STRICT;
CREATE INDEX collect_outbox_dispatch ON collect_notification_outbox(status,created_at,id);
CREATE TRIGGER collect_outbox_insert_queued BEFORE INSERT ON collect_notification_outbox
WHEN NEW.status!='queued' OR NEW.attempt_count!=0 OR NEW.accepted_at IS NOT NULL OR NEW.delivered_at IS NOT NULL
BEGIN SELECT RAISE(ABORT,'Create a queued notification before any delivery attempt'); END;
CREATE TRIGGER collect_outbox_transition BEFORE UPDATE ON collect_notification_outbox
BEGIN
  SELECT (CASE WHEN NEW.id IS NOT OLD.id OR NEW.recipient_user_id IS NOT OLD.recipient_user_id
    OR NEW.group_id IS NOT OLD.group_id OR NEW.transaction_id IS NOT OLD.transaction_id OR NEW.channel IS NOT OLD.channel
    OR NEW.notification_type IS NOT OLD.notification_type OR NEW.deduplication_key IS NOT OLD.deduplication_key
    OR NEW.payload_json IS NOT OLD.payload_json OR NEW.created_at IS NOT OLD.created_at
    THEN RAISE(ABORT,'Notification identity and payload are immutable') END);
  SELECT (CASE WHEN NOT (
    (OLD.status='queued' AND NEW.status IN ('leased','suppressed')) OR
    (OLD.status='leased' AND NEW.status IN ('queued','send_started','suppressed')) OR
    (OLD.status='send_started' AND NEW.status IN ('accepted','failed_no_send','uncertain')) OR
    (OLD.status='accepted' AND NEW.status IN ('delivered','uncertain')) OR
    (OLD.status='uncertain' AND NEW.status IN ('accepted','delivered','failed_no_send')) OR
    (OLD.status='failed_no_send' AND NEW.status IN ('queued','suppressed')))
    THEN RAISE(ABORT,'Invalid notification transition; uncertain sends cannot be retried') END);
  SELECT (CASE WHEN (OLD.status='queued' AND NEW.status='leased' AND NEW.attempt_count!=OLD.attempt_count+1)
    OR (NOT(OLD.status='queued' AND NEW.status='leased') AND NEW.attempt_count!=OLD.attempt_count)
    THEN RAISE(ABORT,'Attempt count must advance only when acquiring a new lease') END);
  SELECT (CASE WHEN OLD.status='leased' AND NEW.status='send_started'
    AND (NEW.lease_token_sha256 IS NOT OLD.lease_token_sha256 OR NEW.lease_until IS NOT OLD.lease_until)
    THEN RAISE(ABORT,'A send must retain its acquired lease identity') END);
  SELECT (CASE WHEN OLD.status='leased' AND NEW.status='send_started'
    AND (NEW.lease_until<=unixepoch() OR NEW.lease_until<=NEW.updated_at)
    THEN RAISE(ABORT,'An expired notification lease cannot start a send') END);
END;
CREATE TRIGGER collect_outbox_no_delete BEFORE DELETE ON collect_notification_outbox
BEGIN SELECT RAISE(ABORT,'Notification replay evidence cannot be deleted'); END;

CREATE TABLE collect_operations_audit (
  id TEXT PRIMARY KEY NOT NULL CHECK(length(id)=36 AND substr(id,9,1)='-' AND substr(id,14,1)='-' AND substr(id,19,1)='-' AND substr(id,24,1)='-' AND length(replace(id,'-',''))=32 AND replace(id,'-','') NOT GLOB '*[^a-f0-9]*'),
  actor_admin_id TEXT NOT NULL REFERENCES admin_users(id) ON DELETE RESTRICT,
  operation_request_id TEXT REFERENCES collect_operation_requests(id) ON DELETE RESTRICT,
  action TEXT NOT NULL CHECK(length(action) BETWEEN 3 AND 100),
  group_id TEXT REFERENCES collect_groups(id) ON DELETE RESTRICT,
  subject_type TEXT NOT NULL CHECK(length(subject_type) BETWEEN 1 AND 80),
  subject_id TEXT NOT NULL CHECK(length(subject_id) BETWEEN 1 AND 200),
  evidence_json TEXT NOT NULL CHECK(json_valid(evidence_json)),
  occurred_at INTEGER NOT NULL CHECK(occurred_at>0)
) STRICT;
CREATE INDEX collect_operations_audit_group ON collect_operations_audit(group_id,occurred_at,id);
CREATE TRIGGER collect_audit_no_update BEFORE UPDATE ON collect_operations_audit
BEGIN SELECT RAISE(ABORT,'Operational audit evidence is append-only'); END;
CREATE TRIGGER collect_audit_no_delete BEFORE DELETE ON collect_operations_audit
BEGIN SELECT RAISE(ABORT,'Operational audit evidence is append-only'); END;
