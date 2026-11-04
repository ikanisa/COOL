"""Prepare a new, isolated self-hosted Collect release; never start services.

Only the public deployment profile and publishable key enter client.json.
Private configuration is created once, atomically, under a mode0700 directory.
No managed Supabase project, Docker daemon or provider is contacted by prepare.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import sys
sys.dont_write_bytecode=True

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts.supabase.deployment_profile import validate_profile, canonical_profile, profile_sha256
from scripts.self_hosted.frontend_manifest import inventory as frontend_inventory

class FrontendOriginsMustDiffer(ValueError):
    """The self-hosted Admin and public sites need distinct origins."""


DEPLOY = ROOT / 'deploy/self-hosted'
BLOCKED_PARTS = {'node_modules', '.git', '.dart_tool', '__pycache__', 'tests', '.temp'}
SOURCE_ROOTS = ('supabase/functions', 'supabase/migrations', 'supabase/jobs',
                'supabase/retention-inventory.json', 'deploy/platform-admin/src',
                'deploy/platform-supabase-free/local-challenge.mjs', 'deploy/collect-sms',
                'deploy/self-hosted/web-server.mjs', 'deploy/self-hosted/auth-phone-proxy.mjs',
                'deploy/self-hosted/edge-main', 'scripts/self_hosted',
                'scripts/supabase/deployment_profile.py', 'deploy/self-hosted/migrations.lock.json',
                'deploy/self-hosted/images.lock.json', 'scripts/supabase/testing/member-realtime-metadata.sql',
                'scripts/supabase/jobs_config.mjs', 'scripts/supabase/jobs_operator.mjs',
                'scripts/supabase/email_jobs_operator.mjs', 'scripts/supabase/package.json',
                'scripts/supabase/sql-maintenance/operator.mjs','scripts/supabase/sql-maintenance/install.sql.in',
                'scripts/supabase/package-lock.json')
SOURCE_ROOTS+=('deploy/self-hosted/upstream','deploy/self-hosted/upstream.lock.json','deploy/self-hosted/generate-keys.mjs')
PRIVATE_KEYS = ('DATA_KEY_ID', 'DATA_ENCRYPTION_KEY', 'SESSION_KEY_ID', 'SESSION_ENCRYPTION_KEY',
                'COLLECT_JOB_TOKEN', 'COLLECT_EMAIL_JOB_TOKEN', 'ROOT_ADMIN_TOKEN', 'OTP_HMAC_KEY',
                'CALLBACK_ENCRYPTION_KEY', 'COLLECT_SMS_MAINTENANCE_TOKEN', 'COLLECT_SMS_HOOK_SECRET')
PROVIDER_SETTINGS = {
    'SMTP_HOST': '', 'SMTP_PORT': '587', 'SMTP_USER': '', 'SMTP_PASS': '', 'SMTP_ADMIN_EMAIL': '',
    'SMTP_SENDER_NAME': 'Collect', 'GOOGLE_CLIENT_ID': '', 'GOOGLE_SECRET': '',
    'GOTRUE_EXTERNAL_GOOGLE_ENABLED': 'false', 'GOOGLE_AUTH_ENABLED': 'false',
    'AUTH_MEMBER_REGISTRATION_ENABLED': 'false', 'AUTH_ANONYMOUS_ENABLED': 'false',
    'AUTH_SMS_ENABLED': 'false', 'AUTH_WHATSAPP_ENABLED': 'false',
    'AUTH_PHONE_DELIVERY_MODE': 'opensms_hook',
    'GOTRUE_SMS_TWILIO_ACCOUNT_SID': '', 'GOTRUE_SMS_TWILIO_AUTH_TOKEN': '',
    'GOTRUE_SMS_TWILIO_MESSAGE_SERVICE_SID': '', 'GOTRUE_SMS_TWILIO_CONTENT_SID': '',
    'GOTRUE_SMS_TWILIO_VERIFY_ACCOUNT_SID': '', 'GOTRUE_SMS_TWILIO_VERIFY_AUTH_TOKEN': '',
    'GOTRUE_SMS_TWILIO_VERIFY_MESSAGE_SERVICE_SID': '',
    'OPENSMS_BASE_URL': '', 'OPENSMS_APPLICATION_ID': '', 'OPENSMS_APPLICATION_TOKEN': '',
    'OPENSMS_SENDER_LABEL': 'Collect', 'OPENSMS_DISPATCH_TTL_SECONDS': '120',
    'TURNSTILE_SITE_KEY': '', 'TURNSTILE_SECRET_KEY': '',
    'COLLECT_SMS_ENABLED': 'false', 'COLLECT_SMS_APPROVAL_SHA256': '',
    'DISPATCH_PAUSED': 'true', 'FCM_ENABLED': 'false', 'RETENTION_AUTO_PURGE': 'false',
    'OTP_REQUIRE_READY_GATEWAY': 'true', 'REQUIRE_ACTUAL_PARTS': 'true',
    'OTP_SEGMENT_INTERVAL_MS': '10000', 'MESSAGE_RETENTION_DAYS': '0', 'CALLBACK_ALLOWED_HOSTS': '',
    'OPENSMS_FCM_PROJECT_ID': '', 'OPENSMS_FCM_CLIENT_EMAIL': '', 'OPENSMS_FCM_PRIVATE_KEY': '',
    'COLLECT_RECEIPT_SMS_ENABLED': 'false', 'OPENSMS_RECEIPT_BASE_URL': '',
    'OPENSMS_RECEIPT_APPLICATION_ID': '', 'OPENSMS_RECEIPT_APPLICATION_TOKEN': '',
    'COLLECT_RECEIPT_SMS_APPROVAL_SHA256': '',
    'COLLECT_CONTRIBUTION_EMAIL_ENABLED': 'false', 'COLLECT_JOBS_EMAIL_APPROVAL_SHA256': '',
    'COLLECT_EMAIL_ADMITTED_FROM': '', 'COLLECT_NOTICE_SMTP_PASSWORD': '',
    'COLLECT_PUSH_ENABLED': 'false', 'FCM_PROJECT_ID': '', 'FCM_ANDROID_PACKAGE': 'app.cool.mobile',
    'FCM_SERVICE_ACCOUNT_JSON': '', 'COLLECT_JOBS_PUSH_APPROVAL_SHA256': '', 'COLLECT_PUSH_ADMITTED_FROM': '',
    'MOMO_PROCESSING_PAUSED': 'true', 'MOMO_AI_ENABLED': 'false', 'MOMO_AI_MODEL': '', 'OPENAI_API_KEY': '',
    'COLLECT_JOBS_MODE': 'maintenance_only', 'COLLECT_JOBS_PROCESSING_APPROVAL_SHA256': '',
    'ROSTER_DECODER_PROTOCOL': '', 'ROSTER_DECODER_URL': '', 'ROSTER_DECODER_SECRET': '', 'ROSTER_DECODER_BUILD_SHA256': '',
    'ROSTER_AI_APPROVAL_JSON': '', 'ROSTER_AI_APPROVAL_SHA256': '', 'ROSTER_AI_MODEL': '',
    'OPENAI_PROJECT_ID': '', 'OPENAI_ORGANIZATION_ID': '',
    'PRIVACY_RETENTION_V2_APPROVAL_SHA256': '',
}

def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def write_json(path: Path, value, *, private=False):
    with path.open('x', encoding='utf8') as out:
        os.chmod(path, 0o600 if private else 0o644)
        json.dump(value, out, sort_keys=True, indent=2)
        out.write('\n')

_VENDOR_ROOT='deploy/self-hosted/upstream'
_VENDOR_LOCK='deploy/self-hosted/upstream.lock.json'
_IMAGE_LOCK='deploy/self-hosted/images.lock.json'
_SOURCE_FILE_LIMIT=8*1024*1024
_SOURCE_TOTAL_LIMIT=100*1024*1024
_SOURCE_FILE_COUNT=4096
_SOURCE_DIRECTORY_COUNT=65536
_SOURCE_DEPTH=512

def _relative_parts(name):
    if not isinstance(name,str) or not name or '\0' in name or '\\' in name:
        raise ValueError('Safe relative source path required')
    value=PurePosixPath(name)
    if value.is_absolute() or not value.parts or '..' in value.parts or str(value)!=name:
        raise ValueError('Safe relative source path required')
    return value.parts

def _directory_flags():
    if not all(hasattr(os,name) for name in ('O_DIRECTORY','O_NOFOLLOW','O_NONBLOCK')):
        raise ValueError('Physical source traversal unavailable')
    return os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW

def _same_inode(first,second):
    return (first.st_dev,first.st_ino)==(second.st_dev,second.st_ino)

def _open_physical_root(root):
    root=Path(root).absolute()
    if root.resolve(strict=True)!=root:raise ValueError('Physical source root required')
    fd=os.open(root.anchor,_directory_flags())
    try:
        for part in root.parts[1:]:
            child=_open_child_directory(fd,part)
            previous=fd;fd=child;os.close(previous)
        return fd
    except BaseException:
        os.close(fd);raise

def _open_child_directory(parent,name):
    before=os.stat(name,dir_fd=parent,follow_symlinks=False)
    if not stat.S_ISDIR(before.st_mode):raise ValueError('Physical source directory required')
    child=os.open(name,_directory_flags(),dir_fd=parent)
    actual=os.fstat(child)
    if not stat.S_ISDIR(actual.st_mode) or not _same_inode(before,actual):
        os.close(child);raise ValueError('Source directory changed')
    return child

def _capture_inputs(root,names,*,retain=True):
    """Capture bounded source bytes without following links or special files.

    Excluded source directories are never traversed. Vendor is exported in full,
    so excluded-name entries there are refused rather than silently copied.
    """
    root_fd=_open_physical_root(root)
    files=[];content={};modes={};vendor_dirs={};total=0;directories=0
    def capture(parent,entry,name,before):
        nonlocal total
        if name in content:raise ValueError('Duplicate release source')
        fd=os.open(entry,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK,dir_fd=parent)
        try:
            actual=os.fstat(fd)
            if not stat.S_ISREG(actual.st_mode) or not _same_inode(before,actual):raise ValueError('Source file changed')
            if actual.st_size<0 or actual.st_size>_SOURCE_FILE_LIMIT:raise ValueError('Invalid release source size')
            remaining=actual.st_size;data=bytearray()
            while remaining:
                chunk=os.read(fd,min(1024*1024,remaining))
                if not chunk:raise ValueError('Source file changed')
                data.extend(chunk);remaining-=len(chunk)
            if os.read(fd,1):raise ValueError('Source file changed')
            after=os.fstat(fd)
            if (actual.st_size,actual.st_mtime_ns,actual.st_ctime_ns)!=(after.st_size,after.st_mtime_ns,after.st_ctime_ns):raise ValueError('Source file changed')
        finally:os.close(fd)
        data=bytes(data)
        if name.startswith('supabase/migrations/') and name.endswith('.sql') and not data.strip():raise ValueError('Invalid release source size')
        total+=len(data)
        if len(files)>=_SOURCE_FILE_COUNT or total>_SOURCE_TOTAL_LIMIT:raise ValueError('Release source exceeds its review bound')
        files.append({'path':name,'bytes':len(data),'sha256':digest(data)})
        content[name]=data if retain else None;modes[name]=stat.S_IMODE(actual.st_mode)
    def walk(fd,name,vendor):
        nonlocal directories
        directories+=1
        if directories>_SOURCE_DIRECTORY_COUNT or len(PurePosixPath(name).parts)>_SOURCE_DEPTH:raise ValueError('Source directory budget exceeded')
        before=os.fstat(fd)
        if vendor:vendor_dirs[name.removeprefix(_VENDOR_ROOT).lstrip('/')]=stat.S_IMODE(before.st_mode)
        with os.scandir(fd) as entries:
            for entry in entries:
                if entry.name in BLOCKED_PARTS:
                    if vendor:raise ValueError('Excluded vendor entries cannot be exported')
                    continue
                child_name=name+'/'+entry.name
                info=entry.stat(follow_symlinks=False)
                if stat.S_ISDIR(info.st_mode):
                    child=_open_child_directory(fd,entry.name)
                    try:
                        if not _same_inode(info,os.fstat(child)):raise ValueError('Source directory changed')
                        walk(child,child_name,vendor)
                    finally:os.close(child)
                elif stat.S_ISREG(info.st_mode):capture(fd,entry.name,child_name,info)
                else:raise ValueError('Source links and special files are refused')
        after=os.fstat(fd)
        if (before.st_mtime_ns,before.st_ctime_ns)!=(after.st_mtime_ns,after.st_ctime_ns):raise ValueError('Source directory changed')
    try:
        for name in names:
            parts=_relative_parts(name)
            if any(part in BLOCKED_PARTS for part in parts):continue
            parent=os.dup(root_fd)
            try:
                for part in parts[:-1]:
                    child=_open_child_directory(parent,part);os.close(parent);parent=child
                info=os.stat(parts[-1],dir_fd=parent,follow_symlinks=False)
                if stat.S_ISDIR(info.st_mode):
                    child=_open_child_directory(parent,parts[-1])
                    try:
                        if not _same_inode(info,os.fstat(child)):raise ValueError('Source directory changed')
                        walk(child,name,name==_VENDOR_ROOT)
                    finally:os.close(child)
                elif stat.S_ISREG(info.st_mode):capture(parent,parts[-1],name,info)
                else:raise ValueError('Source links and special files are refused')
            finally:os.close(parent)
    finally:os.close(root_fd)
    files.sort(key=lambda item:item['path'])
    manifest={'format':'collect.selfhost.source.v1','files':files,'sha256':digest(json.dumps(files,sort_keys=True,separators=(',',':')).encode())}
    return {'manifest':manifest,'content':content,'modes':modes,'vendor_dirs':vendor_dirs}

def _verified_vendor(snapshot):
    content=snapshot['content'];lock=json.loads(content[_VENDOR_LOCK]);images=json.loads(content[_IMAGE_LOCK])
    if not isinstance(lock,dict) or lock.get('format')!='collect.selfhost.upstream.v1' or lock.get('commit')!='bc27d2661edd09a5d0b8d76ce33da6d4071a756e':raise ValueError('Unreviewed upstream source')
    if not isinstance(lock.get('files'),list) or not 1<=len(lock['files'])<=_SOURCE_FILE_COUNT:raise ValueError('Upstream file inventory changed')
    expected={}
    for item in lock['files']:
        if not isinstance(item,dict):raise ValueError('Upstream file inventory changed')
        name=item.get('path');_relative_parts(name);value=item.get('sha256')
        if name in expected or not isinstance(value,str) or not re.fullmatch(r'[a-f0-9]{64}',value):raise ValueError('Upstream file inventory changed')
        expected[name]=value
    actual={name.removeprefix(_VENDOR_ROOT+'/'):data for name,data in content.items() if name.startswith(_VENDOR_ROOT+'/')}
    if set(actual)!=set(expected):raise ValueError('Upstream file inventory changed')
    if any(digest(actual[name])!=value for name,value in expected.items()):raise ValueError('Upstream source digest mismatch')
    if not isinstance(images,dict) or images.get('format')!='collect.selfhost.images.v1' or images.get('upstream_commit')!=lock['commit'] or not isinstance(images.get('services'),dict):raise ValueError('Image lock format mismatch')
    for item in images['services'].values():
        if not isinstance(item,dict) or not isinstance(item.get('reference'),str) or not re.fullmatch(r'[^\s@]+@sha256:[a-f0-9]{64}',item['reference']):raise ValueError('Immutable container reference required')
    return images

def verify_vendor(*,root=None,snapshot=None):
    if snapshot is None:snapshot=_capture_inputs(ROOT if root is None else root,(_VENDOR_ROOT,_VENDOR_LOCK,_IMAGE_LOCK))
    return _verified_vendor(snapshot)

def source_manifest(root=ROOT):
    return _capture_inputs(root,SOURCE_ROOTS,retain=False)['manifest']

def _assert_source_unchanged(root,snapshot):
    observed=_capture_inputs(root,SOURCE_ROOTS,retain=False)
    if any(observed[key]!=snapshot[key] for key in ('manifest','modes','vendor_dirs')):
        raise ValueError('Release source changed during export')

def _stage_inputs(output,snapshot):
    """Create fresh release trees from captured bytes, without reopening source."""
    root_fd=_open_physical_root(output)
    directories={():root_fd};directory_links={};file_links=[]
    def directory(parts):
        parts=tuple(parts)
        if parts in directories:return directories[parts]
        parent=directory(parts[:-1]);name=parts[-1]
        os.mkdir(name,0o700,dir_fd=parent)
        child=_open_child_directory(parent,name)
        directories[parts]=child;directory_links[parts]=(parent,name)
        return child
    def write(parts,data,mode):
        parent=directory(parts[:-1]);name=parts[-1]
        fd=os.open(name,os.O_RDWR|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW|os.O_NONBLOCK,0o600,dir_fd=parent)
        try:
            remaining=memoryview(data)
            while remaining:
                count=os.write(fd,remaining)
                if count<=0:raise ValueError('Release source copy incomplete')
                remaining=remaining[count:]
            os.fchmod(fd,mode);os.lseek(fd,0,os.SEEK_SET)
            actual=os.fstat(fd);check=hashlib.sha256();size=0
            while True:
                chunk=os.read(fd,1024*1024)
                if not chunk:break
                size+=len(chunk)
                if size>len(data):raise ValueError('Release source copy changed')
                check.update(chunk)
            after=os.fstat(fd)
            if not stat.S_ISREG(after.st_mode) or stat.S_IMODE(after.st_mode)!=mode or size!=len(data) or check.hexdigest()!=digest(data) or (actual.st_size,actual.st_mtime_ns,actual.st_ctime_ns)!=(after.st_size,after.st_mtime_ns,after.st_ctime_ns):
                raise ValueError('Release source copy changed')
            file_links.append((parent,name,after))
        finally:os.close(fd)
    try:
        directory(('source',));directory(('upstream',))
        if '' not in snapshot['vendor_dirs']:raise ValueError('Physical vendor directory required')
        for name in sorted(snapshot['vendor_dirs'],key=lambda value:(len(PurePosixPath(value).parts),value)):
            if name:directory(('upstream',)+_relative_parts(name))
        for item in snapshot['manifest']['files']:
            name=item['path'];parts=_relative_parts(name);data=snapshot['content'][name]
            if not isinstance(data,bytes) or len(data)!=item['bytes'] or digest(data)!=item['sha256']:
                raise ValueError('Captured source identity changed')
            write(('source',)+parts,data,0o644)
            if name.startswith(_VENDOR_ROOT+'/'):
                vendor_name=name.removeprefix(_VENDOR_ROOT+'/')
                write(('upstream',)+_relative_parts(vendor_name),data,snapshot['modes'][name])
        for parent,name,original in file_links:
            linked=os.stat(name,dir_fd=parent,follow_symlinks=False)
            if not stat.S_ISREG(linked.st_mode) or not _same_inode(linked,original) or (linked.st_size,linked.st_mtime_ns,linked.st_ctime_ns)!=(original.st_size,original.st_mtime_ns,original.st_ctime_ns):raise ValueError('Release source copy changed')
        for parts,fd in sorted(directories.items(),key=lambda item:len(item[0]),reverse=True):
            if not parts:continue
            if parts[0]=='source':mode=0o755
            else:
                relative='/'.join(parts[1:]);mode=snapshot['vendor_dirs'][relative]
            os.fchmod(fd,mode)
            parent,name=directory_links[parts];linked=os.stat(name,dir_fd=parent,follow_symlinks=False)
            if not stat.S_ISDIR(linked.st_mode) or stat.S_IMODE(linked.st_mode)!=mode or not _same_inode(linked,os.fstat(fd)):raise ValueError('Release source directory changed')
        if not _same_inode(Path(output).lstat(),os.fstat(root_fd)):raise ValueError('Release directory changed')
    finally:
        for fd in reversed(list(directories.values())):os.close(fd)

def dotenv(values):
    # Compose double-quoted values decode escaped newlines; $$ prevents Compose
    # interpolation of arbitrary provider credentials. No shell sources this file.
    for key in values:
        if not re.fullmatch(r'[A-Z][A-Z0-9_]*',key) or not isinstance(values[key],str) or '\0' in values[key]:
            raise ValueError('Invalid private environment entry')
    return ''.join(k+'='+json.dumps(values[k].replace('$','$$'))+'\n' for k in sorted(values))

CONFIGURATION_FILES=('release.json','compose.json','Caddyfile','images.lock.json','public.env','client.json','frontend-source-manifest.json',
                     'private/keys.json','private/provider-settings.json','private/stack.env','private/functions.env',
                     'private/db-tls/ca.crt','private/db-tls/server.crt')
def seal_configuration(release):
    meta=json.loads((release/'release.json').read_text())
    receipt={'format':'collect.selfhost.configuration.v1','profile_sha256':meta['profile_sha256'],
             'source_sha256':meta['source_sha256'],'files':{name:digest((release/name).read_bytes()) for name in CONFIGURATION_FILES}}
    temp=release/'private/configuration.json.next'
    write_json(temp,receipt,private=True);temp.replace(release/'private/configuration.json')
    return receipt

def tls_keys(directory: Path):
    directory.mkdir(mode=0o700)
    commands=[['openssl','req','-x509','-newkey','rsa:3072','-nodes','-days','3650','-subj','/CN=Collect private database CA',
               '-keyout',str(directory/'ca.key'),'-out',str(directory/'ca.crt')],
              ['openssl','req','-newkey','rsa:3072','-nodes','-subj','/CN=db','-keyout',str(directory/'server.key'),'-out',str(directory/'server.csr')]]
    for command in commands:
        subprocess.run(command,check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=60)
    (directory/'extensions.cnf').write_text('subjectAltName=DNS:db\nextendedKeyUsage=serverAuth\nkeyUsage=digitalSignature,keyEncipherment\n')
    subprocess.run(['openssl','x509','-req','-in',str(directory/'server.csr'),'-CA',str(directory/'ca.crt'),'-CAkey',str(directory/'ca.key'),
                    '-CAcreateserial','-days','397','-extfile',str(directory/'extensions.cnf'),'-out',str(directory/'server.crt')],
                   check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=60)
    for path in directory.iterdir():path.chmod(0o600)
    for name in ('ca.crt','server.crt'):(directory/name).chmod(0o644)
    # The database needs its leaf key, never the authority's private key.
    authority=directory.parent/'db-ca';authority.mkdir(mode=0o700)
    for name in ('ca.key','ca.srl'):
        (directory/name).replace(authority/name)
    shutil.copy2(directory/'ca.crt',authority/'ca.crt')

def build_compose(profile,images,*,upstream_compose=None):
    compose=json.loads((DEPLOY/'upstream/compose.json').read_text() if upstream_compose is None else upstream_compose)
    compose['name']='collect-'+profile['id']
    for name,service in compose['services'].items():
        service.pop('container_name',None)
        service.pop('ports',None)
        service['image']=images['services'][name]['reference']
        service['restart']='unless-stopped'
        service['security_opt']=['no-new-privileges:true']
        service['pids_limit']=512
        service['logging']={'driver':'json-file','options':{'max-size':'10m','max-file':'5'}}
        service['labels']={'com.collect.profile-sha256':'${COLLECT_DEPLOYMENT_PROFILE_SHA256}',
                           'com.collect.source-sha256':'${BUILD_SOURCE_ID}',
                           'com.collect.release-root':'${COLLECT_RELEASE_ROOT}'}
        volumes=[]
        for mount in service.get('volumes',[]):
            if not isinstance(mount,str):raise ValueError('Review new upstream volume syntax')
            host,_,tail=mount.partition(':')
            if host=='./volumes/db/data':host='./data/db'
            elif host=='./volumes/storage':host='./data/storage'
            elif host=='./volumes/snippets':host='./data/snippets'
            elif host=='db-config':host='./data/db-config'
            elif host=='deno-cache':host='./data/deno-cache'
            elif host.startswith('./volumes/'):host='./upstream/'+host[2:]
            else:raise ValueError('Review new upstream mount: '+host)
            volumes.append(host+':'+tail)
        if volumes:service['volumes']=volumes
    compose['volumes']={}
    db=compose['services']['db']
    db['volumes'].append('./private/db-tls:/etc/collect-db-tls:ro')
    db['command']+=['-c','ssl=on','-c','ssl_cert_file=/etc/collect-db-tls/server.crt','-c','ssl_key_file=/etc/collect-db-tls/server.key','-c','timezone=UTC','-c','log_timezone=UTC']
    auth=compose['services']['auth']['environment']
    auth.update({'GOTRUE_JWT_KEYS':'${JWT_KEYS}','GOTRUE_JWT_ISSUER':profile['supabase_origin']+'/auth/v1',
                 'GOTRUE_EXTERNAL_ANONYMOUS_USERS_ENABLED':'${AUTH_ANONYMOUS_ENABLED}',
                 'GOTRUE_EXTERNAL_GOOGLE_ENABLED':'${GOTRUE_EXTERNAL_GOOGLE_ENABLED}',
                 'GOTRUE_EXTERNAL_GOOGLE_CLIENT_ID':'${GOOGLE_CLIENT_ID}', 'GOTRUE_EXTERNAL_GOOGLE_SECRET':'${GOOGLE_SECRET}',
                 'GOTRUE_EXTERNAL_GOOGLE_REDIRECT_URI':profile['supabase_origin']+'/auth/v1/callback',
                 'GOTRUE_EXTERNAL_PHONE_ENABLED':'${ENABLE_PHONE_SIGNUP}', 'GOTRUE_SMS_AUTOCONFIRM':'false',
                 'GOTRUE_SMS_OTP_LENGTH':'6','GOTRUE_SMS_OTP_EXP':'300',
                 'GOTRUE_MAILER_AUTOCONFIRM':'false','GOTRUE_MAILER_SECURE_EMAIL_CHANGE_ENABLED':'true',
                 'GOTRUE_SECURITY_CAPTCHA_ENABLED':'${GOTRUE_SECURITY_CAPTCHA_ENABLED}',
                 'GOTRUE_SECURITY_CAPTCHA_PROVIDER':'turnstile','GOTRUE_SECURITY_CAPTCHA_SECRET':'${TURNSTILE_SECRET_KEY}',
                 'GOTRUE_RATE_LIMIT_EMAIL_SENT':'30','GOTRUE_RATE_LIMIT_SMS_SENT':'30','GOTRUE_RATE_LIMIT_ANONYMOUS_USERS':'10',
                 'GOTRUE_SMS_PROVIDER':'${GOTRUE_SMS_PROVIDER}',
                 **{key:'${'+key+'}' for key in PROVIDER_SETTINGS if key.startswith('GOTRUE_SMS_TWILIO')},
                 'GOTRUE_HOOK_SEND_SMS_ENABLED':'${GOTRUE_HOOK_SEND_SMS_ENABLED}',
                 'GOTRUE_HOOK_SEND_SMS_URI':'http://functions:9000/send-sms-hook',
                 'GOTRUE_HOOK_SEND_SMS_SECRETS':'v1,whsec_${COLLECT_SMS_HOOK_SECRET}'})
    compose['services']['rest']['environment']['PGRST_JWT_SECRET']='${JWT_JWKS}'
    compose['services']['realtime']['environment']['API_JWT_JWKS']='${JWT_JWKS}'
    compose['services']['storage']['environment']['JWT_JWKS']='${JWT_JWKS}'
    functions=compose['services']['functions']
    functions['volumes']=['./source:/home/deno/collect:ro','./source/deploy/self-hosted/edge-main:/home/deno/main:ro','./data/deno-cache:/root/.cache/deno']
    functions['command']=['start','--user-worker-request-idle-timeout','150000','--main-service','/home/deno/main']
    functions['environment']={}
    functions['env_file']=['./private/functions.env']
    # Administrative tools remain inside the private network. The API gateway
    # has no published port; Caddy exposes only public Supabase service paths.
    compose['services']['web']={'image':images['services']['web']['reference'],'restart':'unless-stopped','init':True,
        'working_dir':'/srv/source','command':['node','deploy/self-hosted/web-server.mjs'],
        'volumes':['./source:/srv/source:ro','./assets/admin:/srv/admin:ro','./assets/public:/srv/public:ro'],
        'env_file':['./public.env'],'environment':{'PORT':'8080','SUPABASE_INTERNAL_URL':'http://api-gw:8000'},
        'read_only':True,'cap_drop':['ALL'],'security_opt':['no-new-privileges:true'],'pids_limit':128,
        'depends_on':{'api-gw':{'condition':'service_healthy'}},'logging':{'driver':'json-file','options':{'max-size':'10m','max-file':'5'}}}
    compose['services']['proxy']={'image':images['services']['proxy']['reference'],'restart':'unless-stopped',
        'ports':['80:80/tcp','443:443/tcp','443:443/udp'],'volumes':['./Caddyfile:/etc/caddy/Caddyfile:ro','./data/caddy:/data','./data/caddy-config:/config'],
        'cap_drop':['ALL'],'cap_add':['NET_BIND_SERVICE'],'security_opt':['no-new-privileges:true'],'pids_limit':128,
        'depends_on':['web','api-gw'],'logging':{'driver':'json-file','options':{'max-size':'10m','max-file':'5'}}}
    for name in ('web','proxy'):
        compose['services'][name]['labels']={'com.collect.profile-sha256':'${COLLECT_DEPLOYMENT_PROFILE_SHA256}',
            'com.collect.source-sha256':'${BUILD_SOURCE_ID}','com.collect.release-root':'${COLLECT_RELEASE_ROOT}'}
    return compose

def caddyfile(profile,tls_mode,acme_email):
    if tls_mode=='internal' and profile['environment']!='qualification':raise ValueError('Internal CA is qualification only')
    if tls_mode=='acme' and not re.fullmatch(r'[^\s@{}]+@[^\s@{}]+\.[^\s@{}]+',acme_email or ''):raise ValueError('An ACME contact is required')
    header='{\n admin off\n'+(' email '+acme_email+'\n' if tls_mode=='acme' else '')+'}\n'
    tls=' tls internal\n' if tls_mode=='internal' else ''
    api=profile['supabase_origin'].removeprefix('https://')
    sites=[]
    for origin in sorted({profile['admin_origin'],profile['member_api_origin'],profile['public_origin']}):
        if origin==profile['supabase_origin']:raise ValueError('Supabase and application origins must be distinct')
        sites.append(origin.removeprefix('https://')+' {\n'+tls+' request_body {\n  max_size 16MB\n }\n header Strict-Transport-Security "max-age=31536000"\n reverse_proxy web:8080\n}\n')
    sites.append(api+' {\n'+tls+' request_body {\n  max_size 16MB\n }\n header Strict-Transport-Security "max-age=31536000"\n @auth path /auth/v1/*\n handle @auth {\n  request_body {\n   max_size 16KB\n  }\n  reverse_proxy web:8080\n }\n @api path /rest/v1/* /storage/v1/* /realtime/v1/* /functions/v1/* /graphql/v1\n handle @api {\n  reverse_proxy api-gw:8000\n }\n handle {\n  respond 404\n }\n}\n')
    return header+'\n'.join(sites)

def prepare(profile_path: Path,output: Path,*,tls_mode='acme',acme_email=None):
    profile=validate_profile(json.loads(profile_path.read_text()))
    if profile['mode']!='self_hosted':raise ValueError('Self-hosted profile required')
    if profile['admin_origin']==profile['public_origin']:raise FrontendOriginsMustDiffer('Self-hosted Admin and public origins must differ')
    output=output.absolute()
    if output.exists() or output.parent.resolve()!=output.parent:raise ValueError('Fresh physical release directory required')
    snapshot=_capture_inputs(ROOT,SOURCE_ROOTS);images=verify_vendor(snapshot=snapshot)
    manifest=snapshot['manifest'];frontend=frontend_inventory(ROOT)
    caddy=caddyfile(profile,tls_mode,acme_email)
    os.umask(0o077);output.mkdir(mode=0o700)
    _stage_inputs(output,snapshot)
    _assert_source_unchanged(ROOT,snapshot)
    compose=build_compose(profile,images,upstream_compose=snapshot['content'][_VENDOR_ROOT+'/compose.json'])
    private=output/'private';private.mkdir(mode=0o700)
    subprocess.run(['node',str(output/'source/deploy/self-hosted/generate-keys.mjs'),str(private/'keys.json')],check=True,timeout=30)
    keys=json.loads((private/'keys.json').read_text());tls_keys(private/'db-tls')
    for name in ('admin','public'):(output/'assets'/name).mkdir(parents=True);(output/'assets'/name).chmod(0o755)
    (output/'assets').chmod(0o755)
    (output/'data').mkdir()
    for name in ('db','storage','db-config','deno-cache','snippets','caddy','caddy-config'):(output/'data'/name).mkdir()
    public={'COLLECT_DEPLOYMENT_PROFILE':canonical_profile(profile),'COLLECT_DEPLOYMENT_PROFILE_SHA256':profile_sha256(profile),
            'APP_ENVIRONMENT':profile['environment'],'COLLECT_BACKEND':'supabase','SUPABASE_URL':profile['supabase_origin'],
            'SUPABASE_AUTH_ISSUER':profile['supabase_origin']+'/auth/v1','SUPABASE_PUBLISHABLE_KEY':keys['SUPABASE_PUBLISHABLE_KEY'],
            'SUPABASE_ADMIN_API_URL':profile['admin_origin'],'SUPABASE_API_URL':profile['member_api_origin'],
            'ADMIN_ORIGIN':profile['admin_origin'],'PUBLIC_ORIGIN':profile['public_origin'],'BUILD_SOURCE_ID':manifest['sha256'],
            'COLLECT_ANONYMOUS_AUTH_ENABLED':'false','COLLECT_SMS_AUTH_ENABLED':'false','COLLECT_WHATSAPP_AUTH_ENABLED':'false',
            'COLLECT_GOOGLE_AUTH_ENABLED':'false','AUTH_PHONE_DELIVERY_MODE':'opensms_hook','AUTH_WHATSAPP_ENABLED':'false',
            'COLLECT_ASSISTED_SMS_ENABLED':'false'}
    public.update({'AUTH_CAPTCHA_ENABLED':'true' if profile['environment']=='production' else 'false',
                   'AUTH_CAPTCHA_PROVIDER':'turnstile','AUTH_CAPTCHA_SITE_KEY':''})
    write_json(output/'client.json',public)
    (output/'public.env').write_text(dotenv(public));(output/'public.env').chmod(0o644)
    stack={k:v for k,v in keys.items() if k!='format'}
    stack.update(public)
    stack['COLLECT_RELEASE_ROOT']=str(output)
    stack.update(PROVIDER_SETTINGS)
    stack.update({'POSTGRES_HOST':'db','POSTGRES_DB':'postgres','POSTGRES_PORT':'5432','JWT_EXPIRY':'3600',
        'SUPABASE_PUBLIC_URL':profile['supabase_origin'],'API_EXTERNAL_URL':profile['supabase_origin']+'/auth/v1',
        'SITE_URL':profile['public_origin'],'ADDITIONAL_REDIRECT_URLS':profile['google_callback_origin']+'/functions/v1/collect-api/v1/auth/google/callback',
        'DISABLE_SIGNUP':'false','ENABLE_EMAIL_SIGNUP':'true','ENABLE_EMAIL_AUTOCONFIRM':'false','ENABLE_ANONYMOUS_USERS':'false',
        'ENABLE_PHONE_SIGNUP':'false','ENABLE_PHONE_AUTOCONFIRM':'false','FUNCTIONS_VERIFY_JWT':'false',
        'GOTRUE_SMS_PROVIDER':'twilio','GOTRUE_HOOK_SEND_SMS_ENABLED':'false',
        'PGRST_DB_SCHEMAS':'public,graphql_public','PGRST_DB_MAX_ROWS':'1000','PGRST_DB_EXTRA_SEARCH_PATH':'public',
        'STUDIO_DEFAULT_ORGANIZATION':'Collect','STUDIO_DEFAULT_PROJECT':profile['id'],'POOLER_TENANT_ID':profile['id'],
        'POOLER_DEFAULT_POOL_SIZE':'20','POOLER_MAX_CLIENT_CONN':'100','POOLER_DB_POOL_SIZE':'5','POOLER_PROXY_PORT_TRANSACTION':'6543',
        'IMGPROXY_ENABLE_WEBP_DETECTION':'true','IMGPROXY_AUTO_WEBP':'true',
        'REGION':'stub','STORAGE_TENANT_ID':'stub','GLOBAL_S3_BUCKET':'stub',
        'GOTRUE_SECURITY_CAPTCHA_ENABLED':'true' if profile['environment']=='production' else 'false',
        'MAILER_URLPATHS_CONFIRMATION':'/auth/v1/verify','MAILER_URLPATHS_INVITE':'/auth/v1/verify','MAILER_URLPATHS_RECOVERY':'/auth/v1/verify','MAILER_URLPATHS_EMAIL_CHANGE':'/auth/v1/verify'})
    required=set(re.findall(r'\$\{([A-Z][A-Z0-9_]*)\}',json.dumps(compose)))
    if required-set(stack):raise ValueError('Compose requires explicit values for every interpolation variable')
    (private/'stack.env').write_text(dotenv(stack));(private/'stack.env').chmod(0o600)
    function_settings={k:v for k,v in PROVIDER_SETTINGS.items() if not k.startswith(('SMTP_','GOTRUE_')) and k not in ('GOOGLE_SECRET','GOOGLE_CLIENT_ID')}
    functions={**public,**function_settings,**{k:keys[k] for k in PRIVATE_KEYS},
        'SUPABASE_INTERNAL_URL':'http://api-gw:8000','SUPABASE_SECRET_KEY':keys['SUPABASE_SECRET_KEY'],
        'COLLECT_DATABASE_URL':'postgres://collect_edge:'+keys['COLLECT_EDGE_PASSWORD']+'@db:5432/postgres',
        'COLLECT_SMS_DATABASE_URL':'postgres://collect_sms_edge:'+keys['COLLECT_SMS_EDGE_PASSWORD']+'@db:5432/postgres',
        'COLLECT_DB_CA_PEM':(private/'db-tls/ca.crt').read_text().strip(),
        'COLLECT_GOOGLE_CALLBACK_URL':profile['google_callback_origin']+'/functions/v1/collect-api/v1/auth/google/callback',
        'GOOGLE_WEB_ORIGINS':profile['public_origin']+','+profile['member_api_origin'],
        'AUTH_SEND_SMS_SECRET':'v1,whsec_'+keys['COLLECT_SMS_HOOK_SECRET'],'AUTH_PROJECT_ID':profile['id'],
        'COLLECT_PRIVATE_BUCKET':'collect-evidence'}
    (private/'functions.env').write_text(dotenv(functions));(private/'functions.env').chmod(0o600)
    write_json(private/'provider-settings.json',PROVIDER_SETTINGS,private=True)
    write_json(output/'source-manifest.json',manifest)
    write_json(output/'frontend-source-manifest.json',frontend)
    write_json(output/'images.lock.json',images)
    write_json(output/'compose.json',compose)
    (output/'Caddyfile').write_text(caddy)
    write_json(output/'release.json',{'format':'collect.selfhost.release.v1','profile':profile,'profile_sha256':profile_sha256(profile),
        'source_sha256':manifest['sha256'],'upstream_commit':images['upstream_commit'],'tls_mode':tls_mode,
        'frontend_source_sha256':frontend['sha256'],'frontend_source_complete':frontend['complete'],
        'state':'prepared_not_started','providers_enabled':False,'database_initialized':False,'assets_installed':False})
    seal_configuration(output)
    return {'format':'collect.selfhost.prepared.v1','profile_sha256':profile_sha256(profile),'source_sha256':manifest['sha256'],
            'services':len(compose['services']),'started':False,'providers_enabled':False}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--tls',choices=['acme','internal'],default='acme');parser.add_argument('--acme-email')
    args=parser.parse_args()
    try:print(json.dumps(prepare(args.profile,args.output,tls_mode=args.tls,acme_email=args.acme_email),sort_keys=True))
    except (ValueError,OSError,subprocess.SubprocessError) as error:
        print('Preparation refused: '+type(error).__name__+'. Private values were not printed.',file=sys.stderr);sys.exit(1)
