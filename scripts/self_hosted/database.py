"""Install a fresh self-hosted schema with exact source and transaction receipts.

The first nine migrations prepare the application foundation. SQL10 is gated
by a separately reviewed catalog binding for this actual pinned installation.
An observation never automatically becomes an approval. Existing installations
must use the retained source-upgrade/cutover protocol, not this fresh installer.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
sys.dont_write_bytecode=True
import uuid
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from scripts.self_hosted.release_operator import Operator
from scripts.supabase.deployment_profile import canonical_profile

BASELINE='dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3'
HOSTED_METADATA='62bf00d15d1bd950a764048c51b1c50558784c0d8f8618ec0b0ca32ea8173440'
SQL10='20261022200028_collect_private_member_realtime.sql'
HEX=re.compile(r'[a-f0-9]{64}')
def sha(value):return hashlib.sha256(value).hexdigest()
def literal(value):return "'"+str(value).replace("'","''")+"'"
def canonical(value):return json.dumps(value,sort_keys=True,separators=(',',':'))

def migrations(source):
    lock=json.loads((source/'deploy/self-hosted/migrations.lock.json').read_text())
    if lock.get('format')!='collect.selfhost.migrations.v1':raise ValueError('Reviewed migration manifest required')
    files=lock['migrations'];names=[m['name'] for m in files]
    actual=sorted(p.name for p in (source/'supabase/migrations').iterdir() if p.is_file())
    if names!=sorted(set(names)) or names!=actual or len(names)<23:raise ValueError('Exact full migration inventory required')
    for item in files:
        if set(item)!= {'name','sha256','transaction'} or not re.fullmatch(r'\d{14}_[a-z0-9_]+\.sql',item['name']) or not HEX.fullmatch(item['sha256']) or item['transaction'] not in ('outer','wrap'):raise ValueError('Exact migration record required')
        path=source/'supabase/migrations'/item['name']
        if path.resolve()!=path or sha(path.read_bytes())!=item['sha256']:raise ValueError('Migration bytes changed')
    return files

def transaction_sql(sql,record,profile_sha,operation):
    # Retain every original statement. The only added statement journals its
    # committed result in that same transaction. Source and executed digests
    # are separate; SQL10's reviewed metadata substitution is explicit.
    receipt="INSERT INTO supabase_migrations.collect_installation_steps(version,source_sha256,rendered_sha256,profile_sha256,operation_id) VALUES("+','.join(literal(v) for v in [record['name'],record['sha256'],sha(sql.encode()),profile_sha,str(operation)])+");\n"
    if record['transaction']=='outer':
        end=re.search(r'\nCOMMIT;\s*\Z',sql)
        if not end or not re.search(r'^BEGIN(?: ISOLATION LEVEL READ COMMITTED READ WRITE)?;\s*$',sql,flags=re.M):raise ValueError('Reviewed transaction envelope changed')
        return sql[:end.start()]+'\n'+receipt+sql[end.start():]
    if re.search(r'^(?:BEGIN|COMMIT|ROLLBACK);\s*$',sql,flags=re.M):raise ValueError('Unexpected transaction boundary')
    return 'BEGIN;\nSET LOCAL lock_timeout=\'5s\';\nSET LOCAL statement_timeout=\'60s\';\n'+sql+'\n'+receipt+'COMMIT;\n'

def validate_binding(value,op,records,metadata_sha):
    expected={'format','status','profile_sha256','source_sha256','images_sha256','metadata_sha256','metadata_expression_sha256','sql10_source_sha256','sql10_rendered_sha256','review_evidence_sha256'}
    if not isinstance(value,dict) or set(value)!=expected or value['format']!='collect.selfhost.realtime-binding.v1' or value['status']!='reviewed':raise ValueError('Reviewed platform binding required')
    if any(not HEX.fullmatch(value[k]) for k in expected-{'format','status'}):raise ValueError('Exact binding digest required')
    sql=(op.root/'source/supabase/migrations'/SQL10).read_text()
    rendered=sql.replace("'"+HOSTED_METADATA+"'","'"+metadata_sha+"'")
    if sql.count("'"+HOSTED_METADATA+"'")!=2 or rendered.replace("'"+metadata_sha+"'","'"+HOSTED_METADATA+"'")!=sql:raise ValueError('Only two reviewed metadata literals may change')
    expression=op.root/'source/scripts/supabase/testing/member-realtime-metadata.sql'
    exact={'profile_sha256':op.meta['profile_sha256'],'source_sha256':op.meta['source_sha256'],
        'images_sha256':sha((op.root/'images.lock.json').read_bytes()),'metadata_sha256':metadata_sha,
        'metadata_expression_sha256':sha(expression.read_bytes()),'sql10_source_sha256':next(m['sha256'] for m in records if m['name']==SQL10),
        'sql10_rendered_sha256':sha(rendered.encode())}
    if any(value[k]!=v for k,v in exact.items()):raise ValueError('Platform binding does not match this release or actual database')
    return rendered

class DatabaseInstaller:
    def __init__(self,op):self.op=op;self.records=migrations(op.root/'source')
    def ensure_journal(self):
        profile=self.op.meta['profile_sha256']
        self.op.sql("""BEGIN; SET LOCAL lock_timeout='5s'; SELECT pg_advisory_xact_lock(7346371,3);
DO $$BEGIN IF current_user<>'postgres' OR session_user<>'postgres' OR current_setting('server_version_num')::int/10000<>17 THEN RAISE EXCEPTION 'native_owner_pg17_required';END IF;
IF to_regclass('supabase_migrations.collect_installation_steps') IS NULL AND (to_regnamespace('app') IS NOT NULL OR to_regnamespace('private') IS NOT NULL OR to_regrole('collect_edge') IS NOT NULL OR to_regrole('collect_sms_edge') IS NOT NULL) THEN RAISE EXCEPTION 'fresh_installation_required';END IF; END$$;
CREATE SCHEMA IF NOT EXISTS supabase_migrations AUTHORIZATION postgres;
CREATE TABLE IF NOT EXISTS supabase_migrations.collect_installation_steps(
version text PRIMARY KEY, source_sha256 text NOT NULL CHECK(source_sha256~'^[a-f0-9]{64}$'),
rendered_sha256 text NOT NULL CHECK(rendered_sha256~'^[a-f0-9]{64}$'), profile_sha256 text NOT NULL CHECK(profile_sha256~'^[a-f0-9]{64}$'),
operation_id uuid NOT NULL UNIQUE, committed_at timestamptz NOT NULL DEFAULT clock_timestamp());
REVOKE ALL ON supabase_migrations.collect_installation_steps FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION supabase_migrations.collect_installation_retain() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,pg_temp AS $retain$ BEGIN RAISE EXCEPTION 'installation_history_is_immutable' USING ERRCODE='42501';END;$retain$;
REVOKE ALL ON FUNCTION supabase_migrations.collect_installation_retain() FROM PUBLIC,anon,authenticated,service_role;
DO $retain_trigger$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='supabase_migrations.collect_installation_steps'::regclass AND tgname='collect_installation_retain') THEN CREATE TRIGGER collect_installation_retain BEFORE UPDATE OR DELETE OR TRUNCATE ON supabase_migrations.collect_installation_steps FOR EACH STATEMENT EXECUTE FUNCTION supabase_migrations.collect_installation_retain();END IF;END;$retain_trigger$;
ALTER TABLE supabase_migrations.collect_installation_steps ENABLE ALWAYS TRIGGER collect_installation_retain;
DO $$BEGIN IF EXISTS(SELECT 1 FROM supabase_migrations.collect_installation_steps WHERE profile_sha256<>"""+literal(profile)+""") THEN RAISE EXCEPTION 'installation_profile_mismatch';END IF;END$$;COMMIT;""")
    def applied(self):
        raw=self.op.sql("SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY version),'[]'::jsonb) FROM supabase_migrations.collect_installation_steps s;").decode().strip()
        rows=json.loads(raw)
        allowed={m['name']:m for m in self.records}
        for row in rows:
            if row['version'] not in allowed or row['source_sha256']!=allowed[row['version']]['sha256'] or row['profile_sha256']!=self.op.meta['profile_sha256']:raise ValueError('Retained migration receipt changed')
        if [r['version'] for r in rows]!=[m['name'] for m in self.records[:len(rows)]]:raise ValueError('Applied migrations must be an exact prefix')
        return {r['version']:r for r in rows}
    def apply_records(self,records,rendered10=None):
        applied=self.applied();done=[]
        for record in records:
            sql=rendered10 if record['name']==SQL10 else (self.op.root/'source/supabase/migrations'/record['name']).read_text()
            if sql is None:raise ValueError('Reviewed platform SQL required')
            if record['name'] in applied:
                if applied[record['name']]['rendered_sha256']!=sha(sql.encode()):raise ValueError('Executed migration identity changed')
                continue
            self.op.sql(transaction_sql(sql,record,self.op.meta['profile_sha256'],uuid.uuid4()))
            done.append(record['name'])
        return done
    def foundation(self):
        self.op.docker_preflight();self.ensure_journal()
        if len(self.applied())>9:raise ValueError('Foundation already passed; use reviewed installation readback')
        done=self.apply_records(self.records[:9])
        # This membership is part of SQL10's reviewed catalog and must precede
        # its capture. Retrying verifies the existing credential; no rotation.
        keys=json.loads((self.op.root/'private/keys.json').read_text());password=keys['COLLECT_EDGE_PASSWORD']
        if not re.fullmatch(r'[a-f0-9]{64}',password):raise ValueError('Generated runtime credential required')
        self.op.sql("BEGIN; DO $$BEGIN IF to_regrole('collect_edge') IS NULL THEN CREATE ROLE collect_edge LOGIN NOINHERIT NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOREPLICATION PASSWORD "+literal(password)+"; GRANT collect_runtime TO collect_edge;ELSIF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='collect_edge' AND rolcanlogin AND NOT(rolsuper OR rolbypassrls OR rolinherit OR rolcreatedb OR rolcreaterole OR rolreplication)) OR NOT pg_has_role('collect_edge','collect_runtime','MEMBER') THEN RAISE EXCEPTION 'exact_runtime_login_required';END IF;END$$;COMMIT;")
        return {'foundation_installed':True,'new_migrations':done,'platform_review_required':True,'public_started':False}
    def capture(self,output):
        self.op.docker_preflight()
        if len(self.applied())!=9:raise ValueError('Exact nine-migration inactive foundation required')
        expression=(self.op.root/'source/scripts/supabase/testing/member-realtime-metadata.sql').read_text().strip().rstrip(';')
        raw=self.op.sql("SELECT jsonb_build_object('metadata',m,'metadata_sha256',encode(sha256(convert_to(m::text,'UTF8')),'hex')) FROM ("+expression+") q(m);").decode().strip()
        observed=json.loads(raw)
        receipt={'format':'collect.selfhost.platform-observation.v1','status':'observed_not_admitted','profile_sha256':self.op.meta['profile_sha256'],
            'source_sha256':self.op.meta['source_sha256'],'images_sha256':sha((self.op.root/'images.lock.json').read_bytes()),
            'metadata_expression_sha256':sha((self.op.root/'source/scripts/supabase/testing/member-realtime-metadata.sql').read_bytes()),**observed}
        with output.open('x') as stream:json.dump(receipt,stream,sort_keys=True,indent=2);stream.write('\n')
        return {'observed':True,'approved':False,'metadata_sha256':observed['metadata_sha256']}
    def complete(self,binding_path):
        self.op.docker_preflight();self.ensure_journal()
        rows=self.applied()
        if len(rows)<9:raise ValueError('Foundation required')
        binding=json.loads(binding_path.read_text())
        if len(rows)==9:
            expression=(self.op.root/'source/scripts/supabase/testing/member-realtime-metadata.sql').read_text().strip().rstrip(';')
            metadata=self.op.sql("SELECT encode(sha256(convert_to(m::text,'UTF8')),'hex') FROM ("+expression+") q(m);").decode().strip()
        else:metadata=binding['metadata_sha256'] # SQL10 adds policies; retained exact executed receipt proves its initial catalog.
        rendered=validate_binding(binding,self.op,self.records,metadata)
        done=self.apply_records(self.records[9:],rendered)
        # Gateway's separate role does not gain app/private privileges.
        keys=json.loads((self.op.root/'private/keys.json').read_text());password=keys['COLLECT_SMS_EDGE_PASSWORD']
        if not re.fullmatch(r'[a-f0-9]{64}',password):raise ValueError('Generated gateway credential required')
        self.op.sql("BEGIN; DO $$BEGIN IF to_regrole('collect_sms_edge') IS NULL THEN CREATE ROLE collect_sms_edge LOGIN NOINHERIT NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOREPLICATION PASSWORD "+literal(password)+";GRANT collect_sms_runtime TO collect_sms_edge;ELSIF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='collect_sms_edge' AND rolcanlogin AND NOT(rolsuper OR rolbypassrls OR rolinherit OR rolcreatedb OR rolcreaterole OR rolreplication)) OR NOT pg_has_role('collect_sms_edge','collect_sms_runtime','MEMBER') THEN RAISE EXCEPTION 'exact_gateway_login_required';END IF;END$$;COMMIT;")
        return {'migration_count':len(self.applied()),'new_migrations':done,'controller_initialized':False,'public_started':False}
    def initialize(self,operation):
        self.op.docker_preflight()
        if len(self.applied())!=len(self.records):raise ValueError('Full schema required')
        profile=canonical_profile(self.op.profile);source=self.op.meta['source_sha256'];digest=self.op.meta['profile_sha256']
        self.op.sql('BEGIN;SELECT private.collect_bind_deployment('+','.join(literal(v) for v in [str(operation),profile,digest])+');DO $$BEGIN IF EXISTS(SELECT 1 FROM private.collect_fence_control) THEN IF NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode=\'open\' AND epoch=1 AND operation_id='+literal(operation)+'::uuid AND source_sha256='+literal(source)+' AND baseline_manifest_sha256='+literal(BASELINE)+') THEN RAISE EXCEPTION \'initialization_readback_conflict\';END IF;ELSE PERFORM private.collect_fence_initialize('+','.join(literal(v) for v in [str(operation),source,BASELINE])+');END IF;END$$;COMMIT;')
        return {'profile_bound':True,'source_sha256':source,'controller':'open','public_started':False,'provider_activation':False}

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--release',type=Path,required=True);p.add_argument('action',choices=['foundation','capture','complete','initialize']);p.add_argument('--binding',type=Path);p.add_argument('--output',type=Path);p.add_argument('--operation-id',type=uuid.UUID);p.add_argument('--apply',action='store_true');a=p.parse_args()
    try:
        installer=DatabaseInstaller(Operator(a.release))
        if a.action=='capture':
            if a.output is None:raise ValueError('Fresh capture output required')
            result=installer.capture(a.output)
        elif not a.apply:result={'planned':True,'applied':False,'action':a.action}
        elif a.action=='complete':
            if a.binding is None:raise ValueError('Reviewed platform binding required')
            result=installer.complete(a.binding)
        elif a.action=='initialize':
            if a.operation_id is None:raise ValueError('Retained operation UUID required')
            result=installer.initialize(a.operation_id)
        else:result=installer.foundation()
        print(json.dumps(result,sort_keys=True))
    except (OSError,ValueError,KeyError,RuntimeError) as error:
        print(json.dumps({'status':'refused_or_unconfirmed','error_class':type(error).__name__,'private_values_disclosed':False}),file=sys.stderr);sys.exit(1)
