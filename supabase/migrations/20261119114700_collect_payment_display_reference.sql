-- Keep the display reference on the payment row throughout its existing lifetime.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='120s';

DO $preflight$
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced') THEN
  RAISE EXCEPTION 'payment_reference_fence_required' USING ERRCODE='55000';
 END IF;
END;$preflight$;

ALTER TABLE app.payments ADD COLUMN payment_reference bigint GENERATED ALWAYS AS IDENTITY
 (START WITH 100000000000 MINVALUE 100000000000 MAXVALUE 999999999999 NO CYCLE);
ALTER TABLE app.payments ADD CONSTRAINT payments_reference_shape CHECK (payment_reference BETWEEN 100000000000 AND 999999999999),
 ADD CONSTRAINT payments_reference_unique UNIQUE (payment_reference);

CREATE FUNCTION private.collect_payment_reference_immutable() RETURNS trigger
 LANGUAGE plpgsql SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 IF NEW.payment_reference IS DISTINCT FROM OLD.payment_reference THEN
  RAISE EXCEPTION 'payment_reference_immutable' USING ERRCODE='42501';
 END IF;
 RETURN NEW;
END;$fn$;
REVOKE ALL ON FUNCTION private.collect_payment_reference_immutable()
 FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE TRIGGER collect_payment_reference_immutable BEFORE UPDATE ON app.payments
 FOR EACH ROW EXECUTE FUNCTION private.collect_payment_reference_immutable();
ALTER TABLE app.payments ENABLE ALWAYS TRIGGER collect_payment_reference_immutable;
COMMIT;
