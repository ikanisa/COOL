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
from pathlib import Path,PurePosixPath
import re
import stat
import subprocess
import sys
sys.dont_write_bytecode=True
import uuid
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from scripts.supabase.deployment_profile import validate_profile,profile_sha256
from scripts.self_hosted.configure import private_file,read_env,read_provider_settings,validated_settings,verify_configuration
from scripts.self_hosted.prepare import FrontendOriginsMustDiffer

_MAX_SOURCE_MANIFEST_BYTES=128*1024*1024
_MAX_SOURCE_DIRECTORIES=65536
_MAX_SOURCE_DEPTH=512

def _read_source_manifest(path):
    """Read a bounded regular control file without following its final link."""
    if not all(hasattr(os,name) for name in ('O_NOFOLLOW','O_NONBLOCK')):
        raise ValueError('Physical source manifest access unavailable')
    before=path.lstat()
    if not stat.S_ISREG(before.st_mode) or before.st_size>_MAX_SOURCE_MANIFEST_BYTES:
        raise ValueError('Physical bounded source manifest required')
    descriptor=os.open(path,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)
    try:
        actual=os.fstat(descriptor)
        if not stat.S_ISREG(actual.st_mode) or (actual.st_dev,actual.st_ino)!=(before.st_dev,before.st_ino) or actual.st_size>_MAX_SOURCE_MANIFEST_BYTES:
            raise ValueError('Physical bounded source manifest required')
        remaining=actual.st_size;data=bytearray()
        while remaining:
            chunk=os.read(descriptor,min(1024*1024,remaining))
            if not chunk:raise ValueError('Source manifest changed')
            data.extend(chunk);remaining-=len(chunk)
        if os.read(descriptor,1):raise ValueError('Source manifest changed')
        after=os.fstat(descriptor)
        if (actual.st_size,actual.st_mtime_ns,actual.st_ctime_ns)!=(after.st_size,after.st_mtime_ns,after.st_ctime_ns):raise ValueError('Source manifest changed')
        return json.loads(bytes(data))
    finally:os.close(descriptor)

def _source_name(name):
    if not isinstance(name,str) or not name or '\0' in name or '\\' in name:
        raise ValueError('Safe relative source path required')
    path=PurePosixPath(name)
    if path.is_absolute() or not path.parts or '..' in path.parts or str(path)!=name:
        raise ValueError('Safe relative source path required')
    return name

def _verify_physical_tree(root,expected,*,capture=None):
    """Verify every file while refusing links and special nodes without following them.

    Directory-relative opens keep each traversal on the directory that was
    inspected. Host custody is still required after verification: a Docker
    bind mount can observe later host changes.
    """
    if not all(hasattr(os,name) for name in ('O_NOFOLLOW','O_DIRECTORY','O_NONBLOCK')):
        raise ValueError('Physical source traversal unavailable')
    root_stat=root.lstat()
    if not stat.S_ISDIR(root_stat.st_mode):raise ValueError('Physical source directory required')
    flags=os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW
    root_fd=os.open(root,flags)
    seen=set();captured=None;directories=0
    def same_inode(left,right):
        return (left.st_dev,left.st_ino)==(right.st_dev,right.st_ino)
    def walk(directory,prefix,depth):
        nonlocal captured,directories
        directories+=1
        if directories>_MAX_SOURCE_DIRECTORIES or depth>_MAX_SOURCE_DEPTH:raise ValueError('Source directory budget exceeded')
        with os.scandir(directory) as entries:
            for entry in entries:
                name=prefix+entry.name
                before=entry.stat(follow_symlinks=False)
                if stat.S_ISDIR(before.st_mode):
                    child=os.open(entry.name,flags,dir_fd=directory)
                    try:
                        actual=os.fstat(child)
                        if not stat.S_ISDIR(actual.st_mode) or not same_inode(before,actual):raise ValueError('Source directory changed')
                        walk(child,name+'/',depth+1)
                    finally:os.close(child)
                elif stat.S_ISREG(before.st_mode):
                    if name not in expected or name in seen:raise ValueError('Unexpected source file')
                    info=expected[name]
                    descriptor=os.open(entry.name,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK,dir_fd=directory)
                    try:
                        actual=os.fstat(descriptor)
                        if not stat.S_ISREG(actual.st_mode) or not same_inode(before,actual):raise ValueError('Source file changed')
                        if actual.st_size!=info['bytes']:raise ValueError('Source file changed')
                        digest=hashlib.sha256();size=0;data=bytearray() if name==capture else None
                        while True:
                            chunk=os.read(descriptor,1024*1024)
                            if not chunk:break
                            digest.update(chunk);size+=len(chunk)
                            if size>info['bytes']:raise ValueError('Source file changed')
                            if data is not None:data.extend(chunk)
                        after=os.fstat(descriptor)
                        if (actual.st_size,actual.st_mtime_ns,actual.st_ctime_ns)!=(after.st_size,after.st_mtime_ns,after.st_ctime_ns) or size!=actual.st_size or digest.hexdigest()!=info['sha256']:
                            raise ValueError('Source file changed')
                        if data is not None:captured=bytes(data)
                    finally:os.close(descriptor)
                    seen.add(name)
                else:raise ValueError('Source links and special files are refused')
    try:
        if not stat.S_ISDIR(os.fstat(root_fd).st_mode) or not same_inode(root_stat,os.fstat(root_fd)):raise ValueError('Source directory changed')
        walk(root_fd,'',0)
    finally:os.close(root_fd)
    if seen!=set(expected):raise ValueError('Source file inventory changed')
    return captured

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
        manifest=_read_source_manifest(self.root/'source-manifest.json')
        if manifest['format']!='collect.selfhost.source.v1' or manifest['sha256']!=self.meta['source_sha256']:raise ValueError('Source identity mismatch')
        if not isinstance(manifest.get('files'),list) or len(manifest['files'])>4096:raise ValueError('Bounded source inventory required')
        if hashlib.sha256(json.dumps(manifest['files'],sort_keys=True,separators=(',',':')).encode()).hexdigest()!=manifest['sha256']:raise ValueError('Source manifest changed')
        expected={};total=0
        for item in manifest['files']:
            if not isinstance(item,dict):raise ValueError('Unique source inventory required')
            name=_source_name(item['path']);size=item['bytes'];digest=item['sha256']
            if name in expected or type(size) is not int or not 0<=size<=8*1024*1024 or not isinstance(digest,str) or not re.fullmatch(r'[a-f0-9]{64}',digest):raise ValueError('Unique bounded source inventory required')
            total+=size
            if total>100*1024*1024:raise ValueError('Bounded source inventory required')
            expected[name]={'bytes':size,'sha256':digest}
        lock_name='deploy/self-hosted/upstream.lock.json'
        if lock_name not in expected or expected[lock_name]['bytes']>8*1024*1024:raise ValueError('Source-bound upstream lock required')
        lock_data=_verify_physical_tree(self.root/'source',expected,capture=lock_name)
        lock=json.loads(lock_data)
        if not isinstance(lock,dict) or lock.get('format')!='collect.selfhost.upstream.v1' or not isinstance(lock.get('commit'),str) or not re.fullmatch(r'[a-f0-9]{40}',lock['commit']) or lock['commit']!=self.meta.get('upstream_commit') or not isinstance(lock.get('files'),list) or not 1<=len(lock['files'])<=4096:
            raise ValueError('Exact source-bound upstream lock required')
        upstream={}
        for item in lock['files']:
            if not isinstance(item,dict):raise ValueError('Unique upstream inventory required')
            name=_source_name(item['path']);digest=item['sha256']
            if name in upstream or not isinstance(digest,str) or not re.fullmatch(r'[a-f0-9]{64}',digest):raise ValueError('Unique upstream inventory required')
            source=expected.get('deploy/self-hosted/upstream/'+name)
            if source is None or source['sha256']!=digest:raise ValueError('Upstream source identity mismatch')
            upstream[name]={'bytes':source['bytes'],'sha256':digest}
        source_upstream={name.removeprefix('deploy/self-hosted/upstream/') for name in expected if name.startswith('deploy/self-hosted/upstream/')}
        if source_upstream!=set(upstream):raise ValueError('Upstream source inventory mismatch')
        _verify_physical_tree(self.root/'upstream',upstream)

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
        # Empty successful diagnostics carry no stderr evidence. Avoid creating
        # a new empty private file on each routine health-check subprocess.
        if result.returncode or result.stderr:retain(result.stderr)
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
        config=self.sensitive_json(self.compose('config','--format','json'))
        if any(name!='proxy' and service.get('ports') for name,service in config['services'].items()):raise ValueError('Only the TLS proxy may publish host ports')
        if any(not re.fullmatch(r'[^\s@]+@sha256:[a-f0-9]{64}',s.get('image','')) for s in config['services'].values()):raise ValueError('All images must be immutable')
        images=json.loads((self.root/'images.lock.json').read_text())['services']
        if set(config['services'])!=set(images)-{'backup'} or any(service['image']!=images[name]['reference'] for name,service in config['services'].items()):raise ValueError('Exact reviewed service images required')
        existing=self.run([self.docker,'ps','-aq','--filter','label=com.docker.compose.project='+self.project]).decode().split()
        if existing:
            rows=self.sensitive_json(self.run([self.docker,'inspect',*existing]))
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

    def auth_inspection(self,args):
        # Docker inspect can return provider values on stdout. Do not persist
        # either stream on failure or timeout, and never include it in errors.
        result=None
        try:result=subprocess.run(args,capture_output=True,timeout=15)
        except (OSError,subprocess.SubprocessError):pass
        # Raise after leaving the handler so the provider-bearing subprocess
        # exception cannot survive as the public exception's __context__.
        if result is None or result.returncode or not isinstance(result.stdout,bytes) or len(result.stdout)>2*1024*1024:
            result=None
            raise ValueError('Running Auth inspection was not confirmed')
        return result.stdout

    def auth_inspection_json(self,args):
        return self.sensitive_json(self.auth_inspection(args))

    def sensitive_json(self,raw):
        try:return json.loads(raw)
        except (ValueError,TypeError):pass
        # JSONDecodeError.doc and UnicodeDecodeError.object may contain the
        # complete secret-bearing inspection response. Do not chain them.
        raw=None
        raise ValueError('Sensitive configuration or inspection was not confirmed')

    def validate_running_auth(self,config,settings):
        """Observe the existing Auth container without restarting or exposing it.

        Compose config hashes have changed across versions and do not alone
        prove the container's environment. Compare the sealed intended values,
        Compose's resolved model, and the actual container plus its pinned image.
        No credential enters argv, a diagnostic, or the returned result. This
        point-in-time check does not lock out another host operator.
        """
        receipt=self.root/'private/configuration.json'
        initial_receipt=hashlib.sha256(receipt.read_bytes()).digest()
        verify_configuration(self.root)
        original=self.sensitive_json((self.root/'compose.json').read_bytes())['services']['auth']
        resolved=config['services']['auth']
        stack=None
        try:stack=read_env(self.root/'private/stack.env')
        except (OSError,ValueError,TypeError,AttributeError):pass
        if stack is None:raise ValueError('Sealed Auth settings cannot be verified')
        if read_provider_settings(self.root/'private/provider-settings.json')!=settings:
            raise ValueError('Sealed Auth settings changed before verification')
        keys=self.sensitive_json((self.root/'private/keys.json').read_bytes())
        if not isinstance(keys,dict):raise ValueError('Sealed Auth settings cannot be verified')
        hook_secret=keys.get('COLLECT_SMS_HOOK_SECRET')
        jwt_keys=keys.get('JWT_KEYS');jwt_secret=keys.get('JWT_SECRET')
        postgres_password=keys.get('POSTGRES_PASSWORD')
        if any(not isinstance(value,str) or not value for value in (hook_secret,jwt_keys,jwt_secret)):
            raise ValueError('Sealed Auth settings cannot be verified')
        if not isinstance(postgres_password,str) or not re.fullmatch(r'[a-f0-9]{64}',postgres_password):
            raise ValueError('Sealed Auth settings cannot be verified')
        template=original.get('environment')
        if original.get('env_file') or not isinstance(template,dict) or not template:
            raise ValueError('Sealed Auth environment cannot be verified')
        substitutions=re.compile(r'\$\{([A-Z][A-Z0-9_]*)\}')
        expected={}
        for key,value in template.items():
            if not isinstance(key,str) or not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*',key):
                raise ValueError('Sealed Auth environment cannot be verified')
            if type(value) is int:value=str(value)
            if not isinstance(value,str) or '$' in substitutions.sub('',value):
                raise ValueError('Sealed Auth environment cannot be verified')
            try:expected[key]=substitutions.sub(lambda match:stack[match[1]],value)
            except KeyError:raise ValueError('Sealed Auth environment cannot be verified') from None
        sms=settings['AUTH_SMS_ENABLED']=='true';whatsapp=settings['AUTH_WHATSAPP_ENABLED']=='true'
        mode=settings['AUTH_PHONE_DELIVERY_MODE']
        semantics={
            'GOTRUE_DB_DRIVER':'postgres',
            'GOTRUE_DB_DATABASE_URL':'postgres://supabase_auth_admin:'+postgres_password+'@db:5432/postgres',
            'API_EXTERNAL_URL':self.profile['supabase_origin']+'/auth/v1',
            'GOTRUE_SITE_URL':self.profile['public_origin'],
            'GOTRUE_URI_ALLOW_LIST':self.profile['google_callback_origin']+'/functions/v1/collect-api/v1/auth/google/callback',
            'GOTRUE_DISABLE_SIGNUP':'false','GOTRUE_EXTERNAL_EMAIL_ENABLED':'true',
            'GOTRUE_MAILER_SECURE_EMAIL_CHANGE_ENABLED':'true',
            **{'GOTRUE_MAILER_URLPATHS_'+suffix:'/auth/v1/verify'
               for suffix in ('INVITE','CONFIRMATION','RECOVERY','EMAIL_CHANGE')},
            'GOTRUE_RATE_LIMIT_EMAIL_SENT':'30','GOTRUE_RATE_LIMIT_SMS_SENT':'30',
            'GOTRUE_RATE_LIMIT_ANONYMOUS_USERS':'10',
            'GOTRUE_JWT_AUD':'authenticated','GOTRUE_JWT_DEFAULT_GROUP_NAME':'authenticated',
            'GOTRUE_JWT_ADMIN_ROLES':'service_role','GOTRUE_JWT_EXP':'3600',
            'GOTRUE_JWT_KEYS':jwt_keys,'GOTRUE_JWT_SECRET':jwt_secret,
            'GOTRUE_JWT_ISSUER':self.profile['supabase_origin']+'/auth/v1',
            'GOTRUE_EXTERNAL_ANONYMOUS_USERS_ENABLED':settings['AUTH_ANONYMOUS_ENABLED'],
            'GOTRUE_EXTERNAL_GOOGLE_ENABLED':settings['GOTRUE_EXTERNAL_GOOGLE_ENABLED'],
            'GOTRUE_EXTERNAL_GOOGLE_CLIENT_ID':settings['GOOGLE_CLIENT_ID'],
            'GOTRUE_EXTERNAL_GOOGLE_SECRET':settings['GOOGLE_SECRET'],
            'GOTRUE_EXTERNAL_GOOGLE_REDIRECT_URI':self.profile['supabase_origin']+'/auth/v1/callback',
            'GOTRUE_EXTERNAL_PHONE_ENABLED':'true' if sms or whatsapp else 'false',
            'GOTRUE_HOOK_SEND_SMS_ENABLED':'true' if mode=='opensms_hook' and sms else 'false',
            'GOTRUE_HOOK_SEND_SMS_URI':'http://functions:9000/send-sms-hook',
            'GOTRUE_HOOK_SEND_SMS_SECRETS':'v1,whsec_'+hook_secret,
            'GOTRUE_SMS_PROVIDER':'twilio' if mode=='opensms_hook' else mode,
            'GOTRUE_SMS_OTP_LENGTH':'6','GOTRUE_SMS_OTP_EXP':'300',
            'GOTRUE_SMS_AUTOCONFIRM':'false','GOTRUE_MAILER_AUTOCONFIRM':'false',
            'GOTRUE_SECURITY_CAPTCHA_ENABLED':'true' if self.profile['environment']=='production' or settings['TURNSTILE_SITE_KEY'] else 'false',
            'GOTRUE_SECURITY_CAPTCHA_PROVIDER':'turnstile',
            'GOTRUE_SECURITY_CAPTCHA_SECRET':settings['TURNSTILE_SECRET_KEY'],
            **{'GOTRUE_'+key:settings[key] for key in ('SMTP_HOST','SMTP_PORT','SMTP_USER','SMTP_PASS','SMTP_ADMIN_EMAIL','SMTP_SENDER_NAME')},
        }
        if mode!='opensms_hook' and (sms or whatsapp):
            prefix='GOTRUE_SMS_'+mode.upper()+'_'
            semantics.update({key:value for key,value in settings.items() if key.startswith(prefix)})
        image=original.get('image')
        # Compose's rendered JSON doubles literal dollars so it can be loaded
        # again. The container inspection below must match the unescaped values.
        rendered={key:value.replace('$','$$') for key,value in expected.items()}
        if (any(expected.get(key)!=value for key,value in semantics.items()) or not isinstance(image,str)
            or not re.fullmatch(r'[^\s@]+@sha256:[a-f0-9]{64}',image)
            or resolved.get('image')!=image or resolved.get('environment')!=rendered):
            raise ValueError('Resolved Auth configuration differs from the sealed release')
        raw_ids=self.auth_inspection([self.docker,'ps','-aq','--no-trunc',
            '--filter','label=com.docker.compose.project='+self.project,
            '--filter','label=com.docker.compose.service=auth'])
        try:ids=raw_ids.decode('ascii').split()
        except UnicodeError:ids=None
        raw_ids=None
        if ids is None:raise ValueError('Running Auth inspection was not confirmed')
        if len(ids)!=1 or not re.fullmatch(r'[a-f0-9]{64}',ids[0]):
            raise ValueError('One existing Auth container is required')
        rows=self.auth_inspection_json([self.docker,'container','inspect',ids[0]])
        images=self.auth_inspection_json([self.docker,'image','inspect',image])
        if not isinstance(rows,list) or len(rows)!=1 or not isinstance(images,list) or len(images)!=1:
            raise ValueError('Running Auth configuration cannot be verified')
        container=rows[0];inspected_image=images[0]
        if not isinstance(container,dict) or not isinstance(inspected_image,dict):
            raise ValueError('Running Auth configuration cannot be verified')
        fields=container.get('Config');state=container.get('State')
        if not isinstance(fields,dict) or not isinstance(state,dict):
            raise ValueError('Running Auth configuration cannot be verified')
        labels=fields.get('Labels');health=state.get('Health')
        wanted={'com.docker.compose.project':self.project,'com.docker.compose.service':'auth',
                'com.docker.compose.oneoff':'False','com.docker.compose.container-number':'1',
                'com.collect.profile-sha256':self.meta['profile_sha256'],
                'com.collect.source-sha256':self.meta['source_sha256'],
                'com.collect.release-root':str(self.root)}
        if (container.get('Id')!=ids[0] or not isinstance(labels,dict)
            or any(labels.get(key)!=value for key,value in wanted.items())
            or state.get('Status')!='running' or state.get('Running') is not True
            or state.get('Paused') is not False or state.get('Restarting') is not False
            or state.get('Dead') is not False or not isinstance(health,dict)
            or health.get('Status')!='healthy' or fields.get('Image')!=image
            or not re.fullmatch(r'sha256:[a-f0-9]{64}',str(inspected_image.get('Id','')))
            or container.get('Image')!=inspected_image['Id']):
            raise ValueError('Running Auth configuration cannot be verified')
        def environment(entries,*,empty_allowed=False):
            if entries is None and empty_allowed:return {}
            if not isinstance(entries,list):raise ValueError('Running Auth environment cannot be verified')
            result={}
            for entry in entries:
                if not isinstance(entry,str) or '=' not in entry or '\0' in entry:
                    raise ValueError('Running Auth environment cannot be verified')
                key,value=entry.split('=',1)
                if not key or key in result:raise ValueError('Running Auth environment cannot be verified')
                result[key]=value
            return result
        image_config=inspected_image.get('Config')
        if not isinstance(image_config,dict):raise ValueError('Running Auth image cannot be verified')
        image_env=environment(image_config.get('Env'),empty_allowed=True)
        if environment(fields.get('Env'))!={**image_env,**expected}:
            raise ValueError('Running Auth environment differs from the sealed release')
        verify_configuration(self.root)
        if hashlib.sha256(receipt.read_bytes()).digest()!=initial_receipt:
            raise ValueError('Sealed configuration changed during Auth verification')

    def publish(self):
        if self.profile['admin_origin']==self.profile['public_origin']:raise FrontendOriginsMustDiffer('Self-hosted Admin and public origins must differ')
        settings=read_provider_settings(self.root/'private/provider-settings.json')
        status=validated_settings(settings,self.profile,self.meta['source_sha256'])
        if self.profile['environment']=='production' and (not status['smtp_configured'] or not settings['TURNSTILE_SECRET_KEY'] or not settings['TURNSTILE_SITE_KEY']):raise ValueError('Production Auth SMTP and abuse controls must be configured')
        config=self.docker_preflight();self.validate_runtime_database()
        from scripts.self_hosted.assets import verify_assets
        verify_assets(self)
        self.validate_running_auth(config,settings)
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
