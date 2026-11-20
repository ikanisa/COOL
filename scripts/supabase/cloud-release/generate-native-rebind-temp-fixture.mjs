// Extract the operator's exact CAS statement and execute it only on pg_temp
// synthetic rows in a transaction ending in ROLLBACK. No live schema or data.
import {readFileSync} from 'node:fs';
const source=readFileSync(new URL('./native-source-rebind-operator.mjs',import.meta.url),'utf8');
const pattern=/db\.query\(`(UPDATE collect_ops\.jobs_config SET native_provider_source_sha256=\$1,[\s\S]*?RETURNING \*)`,/g;
const matches=[...source.matchAll(pattern)];if(matches.length!==1)throw Error('rebind_fixture_source_changed');
const sql=matches[0][1].replaceAll('collect_ops.jobs_config','pg_temp.jobs_config');
console.log(String.raw`
BEGIN;
CREATE TEMP TABLE jobs_config(singleton boolean,enabled boolean,native_provider_source_sha256 text,
 native_provider_approval_sha256 text,native_provider_model_id text,native_provider_used bigint,
 native_provider_limit bigint,native_provider_expires_at timestamptz,untouched text);
CREATE TEMP TABLE financial_effects(marker text);
INSERT INTO pg_temp.jobs_config VALUES(true,false,repeat('a',64),repeat('b',64),'synthetic-model',137,400,
 '2027-01-01T00:00:00Z','original');
DO $test$
DECLARE v record;n integer;
BEGIN
 EXECUTE $q$`+sql+String.raw`$q$ INTO v USING repeat('c',64),repeat('d',64),repeat('a',64),repeat('b',64),
  'synthetic-model','137','400','2027-01-01T00:00:00Z';
 GET DIAGNOSTICS n=ROW_COUNT;
 IF n<>1 OR v.native_provider_source_sha256<>repeat('c',64) OR v.native_provider_approval_sha256<>repeat('d',64)
  OR v.native_provider_used<>137 OR v.native_provider_limit<>400 OR v.native_provider_model_id<>'synthetic-model'
  OR v.native_provider_expires_at<>'2027-01-01T00:00:00Z'::timestamptz OR v.untouched<>'original' THEN
  RAISE EXCEPTION 'provider rebind did not preserve policy';END IF;
 EXECUTE $q$`+sql+String.raw`$q$ INTO v USING repeat('c',64),repeat('d',64),repeat('a',64),repeat('b',64),
  'synthetic-model','137','400','2027-01-01T00:00:00Z';
 GET DIAGNOSTICS n=ROW_COUNT;IF n<>0 THEN RAISE EXCEPTION 'old preimage accepted twice';END IF;
 UPDATE pg_temp.jobs_config SET native_provider_source_sha256=repeat('a',64),native_provider_approval_sha256=repeat('b',64),
  native_provider_used=138;
 EXECUTE $q$`+sql+String.raw`$q$ INTO v USING repeat('c',64),repeat('d',64),repeat('a',64),repeat('b',64),
  'synthetic-model','137','400','2027-01-01T00:00:00Z';
 GET DIAGNOSTICS n=ROW_COUNT;IF n<>0 THEN RAISE EXCEPTION 'counter drift accepted';END IF;
 UPDATE pg_temp.jobs_config SET native_provider_used=137,native_provider_limit=NULL,native_provider_expires_at=NULL;
 EXECUTE $q$`+sql+String.raw`$q$ INTO v USING repeat('c',64),repeat('d',64),repeat('a',64),repeat('b',64),
  'synthetic-model','137',NULL,NULL;
 GET DIAGNOSTICS n=ROW_COUNT;
 IF n<>1 OR v.native_provider_used<>137 OR v.native_provider_limit IS NOT NULL OR v.native_provider_expires_at IS NOT NULL THEN
  RAISE EXCEPTION 'nullable policy not preserved';END IF;
 IF EXISTS(SELECT 1 FROM pg_temp.financial_effects) THEN RAISE EXCEPTION 'unexpected financial effect';END IF;
 RAISE NOTICE 'synthetic provider source rebind CAS fixture passed';
END;$test$;
ROLLBACK;
`);
