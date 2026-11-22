-- Canonical member-first reconciliation. Proposals are suggestions, never
-- verification, settlement, allocation or journal posting. One independent
-- review closes a proposal; approved allocations and review evidence are fixed.
PRAGMA foreign_keys=ON;

CREATE TABLE collect_reconciliation_proposals (
 id TEXT PRIMARY KEY NOT NULL CHECK(length(id)=36),
 transaction_id TEXT NOT NULL,
 group_id TEXT NOT NULL,
 member_user_id TEXT NOT NULL,
 amount_rwf INTEGER NOT NULL CHECK(amount_rwf BETWEEN 1 AND 9007199254740991),
 transaction_version INTEGER NOT NULL CHECK(transaction_version BETWEEN 1 AND 9007199254740990),
 member_version INTEGER NOT NULL CHECK(member_version BETWEEN 1 AND 9007199254740991),
 membership_version INTEGER NOT NULL CHECK(membership_version BETWEEN 1 AND 9007199254740991),
 group_version INTEGER NOT NULL CHECK(group_version BETWEEN 1 AND 9007199254740991),
 payee_version INTEGER NOT NULL CHECK(payee_version BETWEEN 1 AND 9007199254740991),
 payment_identity_json TEXT NOT NULL CHECK(json_valid(payment_identity_json)),
 payee_identity_json TEXT NOT NULL CHECK(json_valid(payee_identity_json)),
 proposed_by_admin_id TEXT NOT NULL REFERENCES admin_users(id) ON DELETE RESTRICT,
 operation_request_id TEXT NOT NULL UNIQUE REFERENCES collect_operation_requests(id) ON DELETE RESTRICT,
 reason TEXT NOT NULL CHECK(length(trim(reason)) BETWEEN 8 AND 1000),
 created_at INTEGER NOT NULL CHECK(created_at>0),
 FOREIGN KEY(transaction_id,group_id) REFERENCES collect_transactions(id,group_id) ON DELETE RESTRICT,
 FOREIGN KEY(group_id,member_user_id) REFERENCES collect_memberships(group_id,user_id) ON DELETE RESTRICT
) STRICT;
CREATE INDEX collect_reconciliation_proposals_transaction ON collect_reconciliation_proposals(transaction_id,created_at,id);
CREATE TRIGGER collect_reconciliation_proposals_no_update BEFORE UPDATE ON collect_reconciliation_proposals
BEGIN SELECT RAISE(ABORT,'Reconciliation proposals are immutable'); END;
CREATE TRIGGER collect_reconciliation_proposals_no_delete BEFORE DELETE ON collect_reconciliation_proposals
BEGIN SELECT RAISE(ABORT,'Reconciliation proposals are immutable'); END;

CREATE TABLE collect_reconciliation_reviews (
 id TEXT PRIMARY KEY NOT NULL CHECK(length(id)=36),
 proposal_id TEXT NOT NULL UNIQUE REFERENCES collect_reconciliation_proposals(id) ON DELETE RESTRICT,
 outcome TEXT NOT NULL CHECK(outcome IN ('approved','rejected')),
 allocation_id TEXT UNIQUE REFERENCES collect_payment_allocations(id) ON DELETE RESTRICT,
 transaction_version INTEGER NOT NULL CHECK(transaction_version BETWEEN 1 AND 9007199254740991),
 reviewed_by_admin_id TEXT NOT NULL REFERENCES admin_users(id) ON DELETE RESTRICT,
 operation_request_id TEXT NOT NULL UNIQUE REFERENCES collect_operation_requests(id) ON DELETE RESTRICT,
 reason TEXT NOT NULL CHECK(length(trim(reason)) BETWEEN 8 AND 1000),
 reviewed_at INTEGER NOT NULL CHECK(reviewed_at>0),
 CHECK((outcome='approved' AND allocation_id IS NOT NULL) OR (outcome='rejected' AND allocation_id IS NULL))
) STRICT;
CREATE INDEX collect_reconciliation_reviews_created ON collect_reconciliation_reviews(reviewed_at,id);
CREATE TRIGGER collect_reconciliation_reviews_no_update BEFORE UPDATE ON collect_reconciliation_reviews
BEGIN SELECT RAISE(ABORT,'Reconciliation reviews are immutable'); END;
CREATE TRIGGER collect_reconciliation_reviews_no_delete BEFORE DELETE ON collect_reconciliation_reviews
BEGIN SELECT RAISE(ABORT,'Reconciliation reviews are immutable'); END;
CREATE TRIGGER collect_reconciliation_review_independent BEFORE INSERT ON collect_reconciliation_reviews
BEGIN
 SELECT (CASE WHEN NEW.reviewed_by_admin_id=(SELECT proposed_by_admin_id FROM collect_reconciliation_proposals WHERE id=NEW.proposal_id)
  OR NOT EXISTS(SELECT 1 FROM admin_users WHERE id=NEW.reviewed_by_admin_id AND status='active' AND role IN ('owner','admin'))
  THEN RAISE(ABORT,'Reconciliation requires an independent administrator') END);
 SELECT (CASE WHEN NEW.outcome='approved' AND NOT EXISTS(
  SELECT 1 FROM collect_reconciliation_proposals p
  JOIN collect_payment_allocations a ON a.id=NEW.allocation_id
  JOIN collect_transactions t ON t.id=p.transaction_id
  JOIN collect_users u ON u.id=p.member_user_id
  JOIN collect_profiles f ON f.user_id=u.id
  JOIN collect_memberships m ON m.user_id=u.id AND m.group_id=p.group_id
  JOIN collect_groups g ON g.id=p.group_id
  JOIN collect_payees y ON y.id=t.payee_id
  WHERE p.id=NEW.proposal_id AND a.transaction_id=p.transaction_id AND a.group_id=p.group_id
   AND a.member_user_id=p.member_user_id AND a.amount_rwf=p.amount_rwf
   AND a.operation_request_id=NEW.operation_request_id AND a.created_by_admin_id=NEW.reviewed_by_admin_id
   AND t.verification_status='confirmation_recorded' AND t.version=NEW.transaction_version
   AND u.status='active' AND u.version=p.member_version AND m.status='active' AND m.version=p.membership_version
   AND g.status='active' AND g.version=p.group_version AND y.status='active' AND y.version=p.payee_version
   AND f.display_name=json_extract(p.payment_identity_json,'$.display_name')
   AND f.momo_provider=json_extract(p.payment_identity_json,'$.momo_provider')
   AND f.momo_number=json_extract(p.payment_identity_json,'$.momo_number')
   AND f.momo_pay_code=json_extract(p.payment_identity_json,'$.momo_pay_code')
   AND f.display_name_recorded=1 AND f.momo_number!=''
   AND y.momo_number_or_code=json_extract(p.payee_identity_json,'$.momo_number_or_code')
   AND y.network=json_extract(p.payee_identity_json,'$.network'))
  THEN RAISE(ABORT,'Reconciliation approval requires current member and payment evidence') END);
END;
CREATE TRIGGER collect_reconciliation_allocation_fixed BEFORE UPDATE OF member_user_id,amount_rwf ON collect_payment_allocations
WHEN (NEW.member_user_id IS NOT OLD.member_user_id OR NEW.amount_rwf IS NOT OLD.amount_rwf)
 AND EXISTS(SELECT 1 FROM collect_reconciliation_reviews WHERE allocation_id=OLD.id)
BEGIN SELECT RAISE(ABORT,'Reviewed reconciliation allocations are immutable'); END;
