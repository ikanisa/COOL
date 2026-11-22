-- Preserve the verification evidence that authorized an existing posting.
-- New verification/correction workflows are outside this storage guard. Do not
-- rewrite the already-applied 0002 foundation or silently reverse a posting.
CREATE TRIGGER collect_transaction_posted_verification
BEFORE UPDATE OF verification_status,verified_by_admin_id,verified_at ON collect_transactions
WHEN (NEW.verification_status IS NOT OLD.verification_status
  OR NEW.verified_by_admin_id IS NOT OLD.verified_by_admin_id
  OR NEW.verified_at IS NOT OLD.verified_at)
  AND EXISTS(SELECT 1 FROM collect_journals WHERE transaction_id=OLD.id AND status='posted')
BEGIN
  SELECT RAISE(ABORT,'Posted transaction verification evidence is immutable');
END;
