"""Operate only an exact prepared Collect deployment on the local Docker host.

The initial action starts private infrastructure. Publishing requires applied
schema, a matching immutable database identity, tested assets and TLS settings.
No reset, force replacement, volume deletion or automatic provider activation.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
sys.dont_write_bytecode=True
import uuid
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from scripts.supabase.deployment_profile import validate_profile,profile_sha256
from scripts.self_hosted.configure import private_file,read_env,validated_settings,verify_configuration
from scripts.self_hosted.prepare import FrontendOriginsMustDiffer

class Operator:
    def __init__(self,release:Path,*,docker='docker'):
        self.root=release.absolute()
        if self.root.resolve(strict=True)!=self.root:raise ValueError('Physical release path required')
        self.meta=json.loads((self.root/'release.json').read_text())
        if self.meta.get('format')!='collect.selfhost.release.v1':raise ValueError('Unknown release')
        profile=validate_profile(self.meta['profile'])
        if profile['mode']!='self_hosted' or profile_sha256(profile)!=self.meta['profile_sha256']:raise ValueError('Deployment identity mismatch')
        self.profile=profile;self.docker=docker;self.project='collect-'+profile['id']
        for name in ('keys.json','provider-settings.json','stack.env','functions.env'):private_file(self.root/'private'/name)
        self.verify_source()
        verify_configuration(self.root)

    def verify_source(self):
        manifest=json.loads((self.root/'source-manifest.json').read_text())
        if manifest['format']!='collect.selfhost.source.v1' or manifest['sha256']!=self.meta['source_sha256']:raise ValueError('Source identity mismatch')
        if hashlib.sha256(json.dumps(manifest['files'],sort_keys=True,separators=(',',':')).encode()).hexdigest()!=manifest['sha256']:raise ValueError('Source manifest changed')
        seen=set()
        for item in manifest['files']:
            name=item['path'];p=self.root/'source'/name
            if name in seen or p.resolve()!=p or not p.is_file() or not p.is_relative_to(self.root/'source'):raise ValueError('Physical unique release source required')
            data=p.read_bytes()
            if len(data)!=item['bytes'] or hashlib.sha256(data).hexdigest()!=item['sha256']:raise ValueError('Release source changed')
            seen.add(name)
        if seen!={p.relative_to(self.root/'source').as_posix() for p in (self.root/'source').rglob('*') if p.is_file()}:raise ValueError('Unexpected source file')

    def run(self,args,*,input_bytes=None,timeout=60):
        # Process diagnostics may contain operational data. Retain privately;
        # the command's argv, SQL, environment and output never enter reports.
        log=self.root/'private'/('operation-'+uuid.uuid4().hex+'.log')
        def retain(stderr):
            fd=os.open(log,os.O_WRONLY|os.O_CREAT|os.O_EXCL|getattr(os,'O_NOFOLLOW',0),0o600)
            with os.fdopen(fd,'wb') as stream:stream.write(stderr)
        try:
            result=subprocess.run(args,input=input_bytes,capture_output=True,timeout=timeout)
        except subprocess.TimeoutExpired as error:
            retained=False
            try:
                # This bounds persisted diagnostics, not subprocess memory or daemon effects.
                stderr=error.stderr or b''
                if len(stderr)>1024*1024:stderr=stderr[:1024*1024]+b'\n[stderr truncated]\n'
                retain(stderr);retained=True
            except OSError:
                # Diagnostic failure must not hide the unknown command outcome.
                pass
            finally:
                error.cmd='operation';error.args=('operation',error.timeout);error.output=None;error.stderr=None
                error.private_diagnostic_retained=retained
            raise
        retain(result.stderr)
        if result.returncode:raise RuntimeError('Operation failed; inspect its private diagnostic')
        return result.stdout

    def compose(self,*args,input_bytes=None,timeout=60):
        return self.run([self.docker,'compose','--project-directory',str(self.root),'--env-file',str(self.root/'private/stack.env'),
            '-f',str(self.root/'compose.json'),'--project-name',self.project,*args],input_bytes=input_bytes,timeout=timeout)

    def docker_preflight(self):
        override=os.environ.get('DOCKER_HOST')
        if override and not override.startswith('unix://'):raise ValueError('Remote Docker endpoints are refused')
        endpoint=json.loads(self.run([self.docker,'context','inspect','--format','{{json .Endpoints.docker.Host}}']))
        if not isinstance(endpoint,str) or not endpoint.startswith('unix://'):raise ValueError('Local Unix Docker context required')
        info=json.loads(self.run([self.docker,'info','--format','{{json .}}']))
        if int(str(info.get('ServerVersion','0')).split('.')[0])<28 or info.get('OSType')!='linux':raise ValueError('Docker28+ Linux engine required')
        config=json.loads(self.compose('config','--format','json'))
        if any(name!='proxy' and service.get('ports') for name,service in config['services'].items()):raise ValueError('Only the TLS proxy may publish host ports')
        if any(not re.fullmatch(r'[^\s@]+@sha256:[a-f0-9]{64}',s.get('image','')) for s in config['services'].values()):raise ValueError('All images must be immutable')
        images=json.loads((self.root/'images.lock.json').read_text())['services']
        if set(config['services'])!=set(images)-{'backup'} or any(service['image']!=images[name]['reference'] for name,service in config['services'].items()):raise ValueError('Exact reviewed service images required')
        existing=self.run([self.docker,'ps','-aq','--filter','label=com.docker.compose.project='+self.project]).decode().split()
        if existing:
            rows=json.loads(self.run([self.docker,'inspect',*existing]))
            for row in rows:
                labels=row['Config'].get('Labels',{})
                if labels.get('com.collect.profile-sha256')!=self.meta['profile_sha256'] or labels.get('com.collect.release-root')!=str(self.root) or labels.get('com.collect.source-sha256')!=self.meta['source_sha256']:raise ValueError('Existing resources belong to another release; explicit cutover required')
        return config

    def prepare_database_tls(self,config):
        image=config['services']['db']['image']
        self.run([self.docker,'pull',image],timeout=60)
        identity=self.run([self.docker,'run','--rm','--network','none','--entrypoint','id',image,'postgres']).decode()
        match=re.search(r'uid=(\d+)\([^)]*\) gid=(\d+)\(',identity)
        if not match or any(int(n)<1 for n in match.groups()):raise ValueError('Pinned database process identity required')
        uid,gid=map(int,match.groups());directory=self.root/'private/db-tls'
        directory.chmod(0o755);(directory/'server.key').chmod(0o600)
        self.run(['openssl','verify','-CAfile',str(directory/'ca.crt'),'-verify_hostname','db',str(directory/'server.crt')])
        # Docker performs ownership changes only inside this exact generated
        # certificate directory, never on the host's account directories/data.
        self.run([self.docker,'run','--rm','--network','none','--user','0:0','--entrypoint','chown','--mount',
            'type=bind,src='+str(directory)+',dst=/keys',image,str(uid)+':'+str(gid),'/keys','/keys/server.key','/keys/server.crt','/keys/ca.crt'])
        return {'postgres_uid':uid,'postgres_gid':gid,'leaf_key_mode':'0600','ca_key_mounted':False}

    def start_private(self):
        config=self.docker_preflight();tls=self.prepare_database_tls(config)
        services=[name for name in config['services'] if name not in ('proxy','web','functions')]
        self.compose('up','-d','--wait','--wait-timeout','55',*services,timeout=60)
        return {'private_services_started':services,'public_listener_started':False,'schema_applied':False,'tls':tls}

    def sql(self,text):
        return self.compose('exec','-T','db','psql','--no-psqlrc','--set=ON_ERROR_STOP=1','--username=postgres','--dbname=postgres','--tuples-only','--no-align',input_bytes=text.encode())

    def provision_runtime_roles(self):
        self.docker_preflight();keys=json.loads((self.root/'private/keys.json').read_text())
        for key in ('COLLECT_EDGE_PASSWORD','COLLECT_SMS_EDGE_PASSWORD'):
            if not re.fullmatch(r'[a-f0-9]{64}',keys[key]):raise ValueError('Generated runtime credential required')
        # Existing logins are deliberately refused. Provision is an initial
        # installation step, never an implicit password rotation on retry.
        sql="""BEGIN; DO $$BEGIN
IF current_user<>'postgres' OR session_user<>'postgres' OR to_regrole('collect_runtime') IS NULL OR to_regrole('collect_sms_runtime') IS NULL THEN RAISE EXCEPTION 'runtime_role_parent_required';END IF;
IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname IN('collect_edge','collect_sms_edge')) THEN RAISE EXCEPTION 'runtime_role_already_exists_verify_instead';END IF;
END$$;
CREATE ROLE collect_edge LOGIN NOINHERIT NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOREPLICATION PASSWORD '"""+keys['COLLECT_EDGE_PASSWORD']+"""';
GRANT collect_runtime TO collect_edge;
CREATE ROLE collect_sms_edge LOGIN NOINHERIT NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOREPLICATION PASSWORD '"""+keys['COLLECT_SMS_EDGE_PASSWORD']+"""';
GRANT collect_sms_runtime TO collect_sms_edge;
COMMIT;"""
        self.sql(sql)
        return {'runtime_roles_created':['collect_edge','collect_sms_edge'],'passwords_disclosed':False}

    def validate_runtime_database(self):
        sha=self.meta['profile_sha256'];source=self.meta['source_sha256']
        if not re.fullmatch(r'[a-f0-9]{64}',sha) or not re.fullmatch(r'[a-f0-9]{64}',source):raise ValueError('Exact release digest required')
        self.sql("SELECT private.collect_assert_deployment('"+sha+"'); DO $$BEGIN IF NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='open' AND source_sha256='"+source+"') THEN RAISE EXCEPTION 'exact_open_source_required';END IF;IF (SELECT count(*) FROM pg_roles WHERE rolname IN('collect_edge','collect_sms_edge') AND rolcanlogin AND NOT rolsuper AND NOT rolbypassrls AND NOT rolinherit AND NOT rolcreaterole AND NOT rolcreatedb AND NOT rolreplication)<>2 THEN RAISE EXCEPTION 'least_privilege_runtime_roles_required';END IF;IF (SELECT count(*) FROM pg_auth_members m JOIN pg_roles member ON member.oid=m.member JOIN pg_roles parent ON parent.oid=m.roleid WHERE member.rolname IN('collect_edge','collect_sms_edge'))<>2 OR EXISTS(SELECT 1 FROM pg_auth_members m JOIN pg_roles member ON member.oid=m.member JOIN pg_roles parent ON parent.oid=m.roleid WHERE member.rolname IN('collect_edge','collect_sms_edge') AND (parent.rolname<>CASE member.rolname WHEN 'collect_edge' THEN 'collect_runtime' ELSE 'collect_sms_runtime' END OR NOT m.set_option OR m.inherit_option OR m.admin_option)) THEN RAISE EXCEPTION 'exact_runtime_membership_required';END IF;END$$;")
        keys=json.loads((self.root/'private/keys.json').read_text())
        for key in ('COLLECT_EDGE_PASSWORD','COLLECT_SMS_EDGE_PASSWORD'):
            if not re.fullmatch(r'[a-f0-9]{64}',keys[key]):raise ValueError('Generated runtime credential required')
        # Credentials go through stdin into a mode0600 transient pgpass file,
        # never an argv, Docker environment, report or process command line.
        # Both logins authenticate over certificate/hostname-verified TLS and
        # prove their exact application role can read this deployment binding.
        script='''set -eu
umask 077
probe_dir=$(mktemp -d /tmp/collect-credential-probe.XXXXXXXX)
trap 'rm -f "$probe_dir/pgpass"; rmdir "$probe_dir"' EXIT
cat > "$probe_dir/pgpass"
export PGPASSFILE="$probe_dir/pgpass" PGSSLMODE=verify-full PGSSLROOTCERT=/etc/collect-db-tls/ca.crt PGCONNECT_TIMEOUT=5
psql --no-psqlrc --no-password --host=db --port=5432 --username=collect_edge --dbname=postgres --set=ON_ERROR_STOP=1 --quiet --tuples-only --no-align --command="BEGIN;SET LOCAL ROLE collect_runtime;SELECT private.collect_assert_deployment('''+"'"+sha+"'"+''');ROLLBACK;"
psql --no-psqlrc --no-password --host=db --port=5432 --username=collect_sms_edge --dbname=postgres --set=ON_ERROR_STOP=1 --quiet --tuples-only --no-align --command="BEGIN;SET LOCAL ROLE collect_sms_runtime;SELECT collect_sms.assert_deployment_profile('''+"'"+sha+"'"+''');ROLLBACK;"
'''
        pgpass='db:5432:postgres:collect_edge:'+keys['COLLECT_EDGE_PASSWORD']+'\ndb:5432:postgres:collect_sms_edge:'+keys['COLLECT_SMS_EDGE_PASSWORD']+'\n'
        result=self.compose('exec','-T','db','sh','-c',script,input_bytes=pgpass.encode()).decode().split()
        if result!=['t','t']:raise ValueError('Both actual runtime TLS authentication probes must succeed')

    def publish(self):
        if self.profile['admin_origin']==self.profile['public_origin']:raise FrontendOriginsMustDiffer('Self-hosted Admin and public origins must differ')
        self.docker_preflight();self.validate_runtime_database()
        settings=json.loads((self.root/'private/provider-settings.json').read_text())
        status=validated_settings(settings,self.profile,self.meta['source_sha256'])
        if self.profile['environment']=='production' and (not status['smtp_configured'] or not settings['TURNSTILE_SECRET_KEY'] or not settings['TURNSTILE_SITE_KEY']):raise ValueError('Production Auth SMTP and abuse controls must be configured')
        from scripts.self_hosted.assets import verify_assets
        verify_assets(self)
        self.compose('up','-d','--wait','--wait-timeout','55','functions','web','proxy',timeout=60)
        return {'public_listener_started':True,'profile_sha256':self.meta['profile_sha256'],'source_sha256':self.meta['source_sha256'],'production_acceptance':'requires runtime/device/provider/recovery evidence'}

    def status(self):
        self.docker_preflight()
        raw=self.compose('ps','--all','--format','json').decode().strip()
        try:rows=json.loads(raw);rows=rows if isinstance(rows,list) else [rows]
        except json.JSONDecodeError:rows=[json.loads(line) for line in raw.splitlines() if line]
        return {'profile_sha256':self.meta['profile_sha256'],'source_sha256':self.meta['source_sha256'],
            'services':[{'service':r.get('Service'),'state':r.get('State'),'health':r.get('Health')} for r in rows]}

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--release',type=Path,required=True)
    p.add_argument('action',choices=['verify-source','start-private','provision-runtime-roles','publish','status']);p.add_argument('--apply',action='store_true');a=p.parse_args()
    try:
        op=Operator(a.release)
        if a.action=='verify-source':result={'source_verified':True,'source_sha256':op.meta['source_sha256']}
        elif a.action!='status' and not a.apply:result={'action':a.action,'planned':True,'applied':False,'profile_sha256':op.meta['profile_sha256']}
        else:result=getattr(op,a.action.replace('-','_'))()
        print(json.dumps(result,sort_keys=True))
    except (OSError,ValueError,KeyError,RuntimeError,subprocess.SubprocessError) as error:
        print(json.dumps({'status':'refused_or_unconfirmed','error_class':type(error).__name__,'private_values_disclosed':False}),file=sys.stderr);sys.exit(1)
