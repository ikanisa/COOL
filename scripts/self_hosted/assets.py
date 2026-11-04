"""Install source/profile-bound frontend builds into a prepared, empty release."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from scripts.self_hosted.release_operator import Operator
from scripts.self_hosted.configure import parse_fcm_account_json,provider_utf8,read_provider_settings

def digest(data):return hashlib.sha256(data).hexdigest()
def tree(directory):
    directory=directory.absolute()
    if directory.resolve()!=directory or not directory.is_dir():raise ValueError('Physical build directory required')
    result=[];total=0
    for path in sorted(directory.rglob('*')):
        if path.is_symlink():raise ValueError('Frontend links are forbidden')
        if not path.is_file():continue
        relative=path.relative_to(directory).as_posix()
        well_known=relative in ('.well-known/assetlinks.json','.well-known/apple-app-site-association')
        if any('\\' in p or p.startswith('.') and not(well_known and p=='.well-known') for p in path.relative_to(directory).parts):raise ValueError('Unexpected frontend path')
        size=path.stat().st_size;total+=size
        if size>64*1024*1024 or total>512*1024*1024 or len(result)>=20000:raise ValueError('Frontend exceeds bounded artifact budget')
        result.append({'path':relative,'bytes':size,'sha256':digest(path.read_bytes())})
    if not any(item['path']=='index.html' for item in result):raise ValueError('Frontend entrypoint missing')
    return result

def verify_assets(op):
    value=json.loads((op.root/'assets-manifest.json').read_text())
    if set(value)!={'format','profile_sha256','source_sha256','frontend_source_sha256','client_config_sha256','build_evidence_sha256','files'} or value['format']!='collect.selfhost.assets.v1':raise ValueError('Exact frontend artifact contract required')
    if value['profile_sha256']!=op.meta['profile_sha256'] or value['source_sha256']!=op.meta['source_sha256'] or value['client_config_sha256']!=digest((op.root/'client.json').read_bytes()) or value['build_evidence_sha256']!=digest((op.root/'assets-build-evidence.json').read_bytes()):raise ValueError('Rebuild frontends for the exact source and configured public settings')
    if value['frontend_source_sha256']!=op.meta['frontend_source_sha256'] or op.meta['frontend_source_complete'] is not True:raise ValueError('Complete exact frontend source provenance required')
    actual=[]
    for surface in ('admin','public'):
        actual.extend({**item,'path':surface+'/'+item['path']} for item in tree(op.root/'assets'/surface))
    if value['files']!=actual:raise ValueError('Frontend artifact inventory or bytes changed')
    return value

def install(op,admin,public,evidence):
    receipt=json.loads(evidence.read_text())
    expected={'format','profile_sha256','source_sha256','frontend_source_sha256','client_config_sha256','toolchain','commands','surfaces'}
    if set(receipt)!=expected or receipt['format']!='collect.selfhost.frontend-build.v1' or not isinstance(receipt['toolchain'],dict) or not receipt['toolchain'] or not isinstance(receipt['commands'],dict) or set(receipt['commands'])!={'admin','public'}:raise ValueError('Reproducible frontend build evidence required')
    for command in receipt['commands'].values():
        if not isinstance(command,list) or not command or any(not isinstance(v,str) or '\0' in v for v in command):raise ValueError('Exact build command array required')
    if receipt['profile_sha256']!=op.meta['profile_sha256'] or receipt['source_sha256']!=op.meta['source_sha256'] or receipt['client_config_sha256']!=digest((op.root/'client.json').read_bytes()):raise ValueError('Build must use this release and its current client configuration')
    if receipt['frontend_source_sha256']!=op.meta['frontend_source_sha256'] or op.meta['frontend_source_complete'] is not True:raise ValueError('Build must bind all actual frontend inputs and required media evidence')
    inventories={'admin':tree(admin),'public':tree(public)}
    if receipt['surfaces']!=inventories:raise ValueError('Build receipt does not match actual artifact bytes')
    keys=json.loads((op.root/'private/keys.json').read_text())
    public_names={'format','ANON_KEY','ANON_KEY_ASYMMETRIC','SUPABASE_PUBLISHABLE_KEY','DASHBOARD_USERNAME'}
    forbidden=[v.encode() for k,v in keys.items() if k not in public_names and isinstance(v,str) and len(v)>=20]
    forbidden.extend(jwk['d'].encode() for jwk in json.loads(keys['JWT_KEYS']) if 'd' in jwk)
    settings=read_provider_settings(op.root/'private/provider-settings.json')
    secret_fields={'SMTP_PASS','GOOGLE_SECRET','TURNSTILE_SECRET_KEY','OPENSMS_APPLICATION_TOKEN','OPENSMS_RECEIPT_APPLICATION_TOKEN',
        'COLLECT_NOTICE_SMTP_PASSWORD','FCM_SERVICE_ACCOUNT_JSON','OPENAI_API_KEY','ROSTER_DECODER_SECRET',
        'GOTRUE_SMS_TWILIO_AUTH_TOKEN','GOTRUE_SMS_TWILIO_VERIFY_AUTH_TOKEN','OPENSMS_FCM_PRIVATE_KEY'}
    account=None
    if settings.get('FCM_SERVICE_ACCOUNT_JSON'):
        account=parse_fcm_account_json(settings['FCM_SERVICE_ACCOUNT_JSON'])
    forbidden.extend(provider_utf8(settings[name]) for name in secret_fields if settings.get(name))
    if account is not None and isinstance(account.get('private_key'),str):
        forbidden.append(provider_utf8(account['private_key']))
    for base,items in ((admin,inventories['admin']),(public,inventories['public'])):
        for item in items:
            data=(base/item['path']).read_bytes()
            if any(secret in data for secret in forbidden):raise ValueError('A private credential was found in a frontend artifact')
    files=[{**item,'path':surface+'/'+item['path']} for surface in ('admin','public') for item in inventories[surface]]
    manifest={'format':'collect.selfhost.assets.v1','profile_sha256':op.meta['profile_sha256'],'source_sha256':op.meta['source_sha256'],
        'frontend_source_sha256':receipt['frontend_source_sha256'],'client_config_sha256':receipt['client_config_sha256'],'build_evidence_sha256':digest(evidence.read_bytes()),'files':files}
    if (op.root/'assets-manifest.json').exists():
        if verify_assets(op)!=manifest:raise ValueError('Existing release assets cannot be replaced')
        return {'installed':True,'readback':True,'files':len(files)}
    if any((op.root/'assets').rglob('*')):
        if any(p.is_file() or p.is_symlink() for p in (op.root/'assets').rglob('*')):raise ValueError('Fresh empty frontend destinations required')
    for surface,base in (('admin',admin),('public',public)):
        for item in inventories[surface]:
            target=op.root/'assets'/surface/item['path'];target.parent.mkdir(parents=True,exist_ok=True)
            with target.open('xb') as output:os.chmod(target,0o644);output.write((base/item['path']).read_bytes())
        for directory in [op.root/'assets'/surface,*(p for p in (op.root/'assets'/surface).rglob('*') if p.is_dir())]:directory.chmod(0o755)
    with (op.root/'assets-build-evidence.json').open('xb') as output:output.write(evidence.read_bytes())
    with (op.root/'assets-manifest.json').open('x') as output:json.dump(manifest,output,sort_keys=True,indent=2);output.write('\n')
    verify_assets(op)
    return {'installed':True,'files':len(files),'source_sha256':op.meta['source_sha256'],'profile_sha256':op.meta['profile_sha256']}

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--release',type=Path,required=True);p.add_argument('--admin',type=Path,required=True);p.add_argument('--public',type=Path,required=True);p.add_argument('--build-evidence',type=Path,required=True);a=p.parse_args()
    try:print(json.dumps(install(Operator(a.release),a.admin,a.public,a.build_evidence),sort_keys=True))
    except (OSError,ValueError,KeyError,RuntimeError) as error:
        print(json.dumps({'status':'refused','error_class':type(error).__name__,'private_values_disclosed':False}),file=sys.stderr);sys.exit(1)
