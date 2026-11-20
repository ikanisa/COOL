-- TEST-ONLY minimal SQL fixture, NOT Collect's deployed schema or migration.
-- Executes the unchanged shared statement plan under SQLite. No production
-- authorization, PostgreSQL RLS, execution-fence trigger or provider is modeled.
PRAGMA foreign_keys=ON;
CREATE TABLE collections(id TEXT PRIMARY KEY,title TEXT NOT NULL);
CREATE TABLE payment_evidence(id TEXT PRIMARY KEY,external_reference TEXT,receiver_network TEXT,receiver_momo_number TEXT,currency TEXT);
CREATE TABLE payments(id TEXT PRIMARY KEY,collection_id TEXT,member_id TEXT,amount_minor INTEGER,currency TEXT,rail TEXT,revision INTEGER,status TEXT,evidence_id TEXT,intent_id TEXT);
CREATE TABLE ledger_entries(id TEXT PRIMARY KEY,payment_id TEXT,collection_id TEXT,member_id TEXT,amount_minor INTEGER,kind TEXT,evidence_id TEXT,actor_user_id TEXT,request_id TEXT,posted_at TEXT,currency TEXT NOT NULL DEFAULT 'RWF',reverses_entry_id TEXT);
CREATE UNIQUE INDEX one_contribution ON ledger_entries(payment_id) WHERE kind='contribution';
CREATE TABLE reconciliations(id TEXT PRIMARY KEY,payment_id TEXT,status TEXT,proposed_by TEXT,proposed_member_id TEXT,approved_by TEXT,approved_at TEXT);
CREATE TABLE admin_bridge_guards(id TEXT PRIMARY KEY,passed INTEGER NOT NULL CHECK(passed=1));
CREATE TABLE momo_receiving_accounts(id TEXT PRIMARY KEY,provider TEXT,public_code TEXT);
CREATE TABLE momo_transactions(id TEXT PRIMARY KEY,receiving_account_id TEXT,event_kind TEXT,provider TEXT,currency TEXT,provider_transaction_id TEXT,has_conflict INTEGER,allocation_state TEXT,mode TEXT);
CREATE TABLE momo_financial_links(transaction_id TEXT PRIMARY KEY,payment_id TEXT UNIQUE,beneficiary_member_id TEXT);
CREATE TABLE contribution_posting_snapshots(ledger_entry_id TEXT PRIMARY KEY,payment_id TEXT UNIQUE,member_balance_after_minor INTEGER,group_balance_after_minor INTEGER,posted_at TEXT);
CREATE TABLE payment_intents(id TEXT PRIMARY KEY,member_id TEXT,status TEXT);
CREATE TABLE notification_preferences(user_id TEXT PRIMARY KEY,payment_updates INTEGER);
CREATE TABLE notification_events(id TEXT PRIMARY KEY,user_id TEXT,event_type TEXT,title TEXT,body TEXT,data_json TEXT,status TEXT,created_at TEXT);
CREATE TABLE audit_log(actor_user_id TEXT,actor_session_id TEXT,action TEXT,entity_type TEXT,entity_id TEXT,request_id TEXT,details_json TEXT,created_at TEXT);
