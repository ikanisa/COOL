// Rollback-only test of the draft retention patch against synthetic pg_temp
// predecessor functions with the same signature, config, ACL and anchor shape.
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const source=readFileSync(new URL('../../../supabase/migrations/20261117210000_burimunsi_held_recovery.sql',import.meta.url),'utf8');
const start=source.indexOf('DO $held_retention$'),end=source.indexOf('END;$held_retention$;',start);
if(start<0||end<0)throw Error('missing_retention_patch');
const catalog="SELECT '{\"private_classes\": []}'::jsonb";
const inventory=String.raw`DECLARE class_name text:=p_request;BEGIN RETURN jsonb_build_object('rows',CASE WHEN class_name=ANY(ARRAY['private:burimunsi_observation_retry_commands','managed:storage_iceberg','private:burimunsi_native_lease_history']::text[]) THEN NULL ELSE 1 END);END;`;
const hash=x=>createHash('sha256').update(x).digest('hex');
const patch=source.slice(start,end+'END;$held_retention$;'.length)
 .replaceAll('private._retention_manifest_catalog_v2','pg_temp._retention_manifest_catalog_v2')
 .replaceAll('private.retention_capture_inventory_v2','pg_temp.retention_capture_inventory_v2')
 .replace('b05ee1ced84adfbde6f9144039cbd062730dece8dfc060f636425fa64c90d032',hash(catalog))
 .replace('9fcadb280a30843d3d1d8a006e556a8532f365e3e0b30596d5336e6ab3c9c336',hash(inventory));
console.log(String.raw`
BEGIN;
CREATE FUNCTION pg_temp._retention_manifest_catalog_v2() RETURNS jsonb LANGUAGE sql IMMUTABLE
 SET search_path=pg_catalog,pg_temp AS $catalog$${catalog}$catalog$;
CREATE FUNCTION pg_temp.retention_capture_inventory_v2(p_operation uuid,p_request text,p_review bigint,p_source text,p_max_rows integer DEFAULT 1000000)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $inventory$${inventory}$inventory$;
REVOKE ALL ON FUNCTION pg_temp._retention_manifest_catalog_v2() FROM PUBLIC;
REVOKE ALL ON FUNCTION pg_temp.retention_capture_inventory_v2(uuid,text,bigint,text,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION pg_temp.retention_capture_inventory_v2(uuid,text,bigint,text,integer) TO collect_runtime;
`);
console.log(patch);
console.log(String.raw`
DO $test$
DECLARE catalog jsonb:=pg_temp._retention_manifest_catalog_v2();name text;rows jsonb;
BEGIN
 IF jsonb_array_length(catalog->'private_classes')<>2 OR EXISTS(
  SELECT 1 FROM jsonb_array_elements(catalog->'private_classes') c
   WHERE c->>'scope'<>'unmapped_private' OR c->'blocked'<>'true'::jsonb) THEN
  RAISE EXCEPTION 'retention categories not blocked';END IF;
 FOREACH name IN ARRAY ARRAY['private:collect_sms_witnesses','private:burimunsi_recovered_sms_holds'] LOOP
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(catalog->'private_classes') c WHERE c->>'name'=name) THEN
   RAISE EXCEPTION 'retention category missing';END IF;
  rows:=pg_temp.retention_capture_inventory_v2(NULL,name,NULL,NULL,1)->'rows';
  IF rows IS DISTINCT FROM 'null'::jsonb THEN RAISE EXCEPTION 'unmapped subject count exposed';END IF;
 END LOOP;
 IF pg_temp.retention_capture_inventory_v2(NULL,'other',NULL,NULL,1)->'rows'<>'1'::jsonb THEN
  RAISE EXCEPTION 'unrelated inventory behavior changed';END IF;
 RAISE NOTICE 'synthetic held-retention registration passed';
END;$test$;
ROLLBACK;
`);
