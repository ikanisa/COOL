BEGIN;

-- The worker still admits at most one native SMS and one ledger item per
-- dispatch. This migration changes only the wake-up cadence, slot identity,
-- and monthly dispatch ceiling; it creates no new data-access path.
DO $schedule_one_minute$
DECLARE
 c collect_ops.jobs_config%ROWTYPE;
 item record;
 p pg_proc%ROWTYPE;
 body text;
 next_body text;
BEGIN
 PERFORM private._collect_fence_require_operator();
 PERFORM pg_advisory_xact_lock(hashtextextended('collect.scheduler.rrlduytparvsjfmegalh',0));
 SELECT * INTO c FROM collect_ops.jobs_config WHERE singleton FOR UPDATE;
 IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced' AND project_ref='rrlduytparvsjfmegalh')
  OR c.enabled OR EXISTS(SELECT 1 FROM collect_ops.jobs_dispatches WHERE state IN('awaiting','unconfirmed'))
  OR NOT EXISTS(SELECT 1 FROM cron.job WHERE jobid=c.cron_job_id AND jobname='collect-jobs-maintenance-v1'
   AND schedule='*/5 * * * *' AND command='SELECT collect_ops.tick_jobs();'
   AND database=current_database() AND username=current_user AND NOT active)
 THEN RAISE EXCEPTION 'one_minute_scheduler_precondition';END IF;

 FOR item IN SELECT * FROM (VALUES
  ('collect_ops.dispatch_jobs(text,uuid)','9a73cbd4c42ea1e8badb24cd176d0a53bf63da55cec2ff60f9a35549258e20fa'),
  ('collect_ops.activate_jobs(text)','9cfc058905f0cb16c5cbc987661ffcbdbdf24d875cda402d54da7eea2e0dcfc7')
 ) AS x(signature,digest) LOOP
  SELECT * INTO p FROM pg_proc WHERE oid=to_regprocedure(item.signature);
  IF NOT FOUND OR pg_get_userbyid(p.proowner)<>'postgres' OR p.prosecdef
   OR p.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog']::text[]
   OR p.proacl::text IS DISTINCT FROM '{postgres=X/postgres}'
   OR encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') IS DISTINCT FROM item.digest
  THEN RAISE EXCEPTION 'one_minute_scheduler_preimage_changed: %',item.signature;END IF;
 END LOOP;

 SELECT prosrc INTO STRICT body FROM pg_proc WHERE oid='collect_ops.dispatch_jobs(text,uuid)'::regprocedure;
 IF length(body)-length(replace(body,'>=10000 THEN',''))<>length('>=10000 THEN')
  OR length(body)-length(replace(body,'/300)*300',''))<>length('/300)*300')
 THEN RAISE EXCEPTION 'one_minute_scheduler_anchor_changed';END IF;
 next_body:=replace(replace(body,'>=10000 THEN','>=50000 THEN'),'/300)*300','/60)*60');
 IF encode(sha256(convert_to(next_body,'UTF8')),'hex')<>'00e49b5d9603cd8564555252cc62b23d667fd9f611c558c46459e4b7580d9f72'
 THEN RAISE EXCEPTION 'one_minute_scheduler_postimage_changed';END IF;
 EXECUTE format('CREATE OR REPLACE FUNCTION collect_ops.dispatch_jobs(p_kind text,p_dispatch_id uuid) RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS %L',next_body);

 SELECT prosrc INTO STRICT body FROM pg_proc WHERE oid='collect_ops.activate_jobs(text)'::regprocedure;
 IF length(body)-length(replace(body,$anchor$schedule='*/5 * * * *'$anchor$,''))<>length($anchor$schedule='*/5 * * * *'$anchor$)
 THEN RAISE EXCEPTION 'one_minute_scheduler_anchor_changed';END IF;
 next_body:=replace(body,$anchor$schedule='*/5 * * * *'$anchor$,$replacement$schedule='* * * * *'$replacement$);
 IF encode(sha256(convert_to(next_body,'UTF8')),'hex')<>'18fb407a536fa422aa539a15b161c75af638a295159f020eebc5af1692c188d3'
 THEN RAISE EXCEPTION 'one_minute_scheduler_postimage_changed';END IF;
 EXECUTE format('CREATE OR REPLACE FUNCTION collect_ops.activate_jobs(p_evidence_sha256 text) RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS %L',next_body);

 -- A new source-bound, quota-verified probe is required before reactivation.
 UPDATE collect_ops.jobs_config SET last_probe_id=NULL WHERE singleton;
 PERFORM cron.alter_job(c.cron_job_id,schedule:='* * * * *',active:=false);
 IF NOT EXISTS(SELECT 1 FROM cron.job WHERE jobid=c.cron_job_id AND jobname='collect-jobs-maintenance-v1'
   AND schedule='* * * * *' AND command='SELECT collect_ops.tick_jobs();'
   AND database=current_database() AND username=current_user AND NOT active)
  OR EXISTS(SELECT 1 FROM collect_ops.jobs_config WHERE singleton AND (enabled OR last_probe_id IS NOT NULL))
 THEN RAISE EXCEPTION 'one_minute_scheduler_postcondition';END IF;
END
$schedule_one_minute$;

COMMIT;
