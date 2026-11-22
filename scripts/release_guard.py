#!/usr/bin/env python3
"""Source-bound release checks with mandatory external provenance for application gates.

Python 3.11+; OpenSSL 3+ verifies application-gate provenance. No network or deployment.
Run on an immutable trusted checkout, not attacker-writable paths or as root.
"""
from __future__ import annotations
import argparse
import datetime as dt
import hashlib
import io
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile
import unicodedata
import zipfile
import zlib

VERSION = '4.0.0'
SCHEMA = 1
UTC = dt.timezone.utc
MAX_FILE = 64 * 1024 * 1024
MAX_JSON = 8 * 1024 * 1024
MAX_TOTAL = 512 * 1024 * 1024
MAX_ENTRIES = 20000
MAX_AGE = 86400
MAX_DEPTH = 4
SKIP = frozenset({'.git', '.gradle', '.kotlin', '__pycache__', 'node_modules', 'build', '.release-evidence'})
DECLARATIONS = frozenset({'toolchain-requirements.json','package.json','package-lock.json','npm-shrinkwrap.json','pnpm-lock.yaml','yarn.lock',
    'pyproject.toml','poetry.lock','uv.lock','deno.json','deno.jsonc','deno.lock','libs.versions.toml',
    'gradle.lockfile','gradle-wrapper.properties','verification-metadata.xml','build.gradle','build.gradle.kts',
    'settings.gradle','settings.gradle.kts'})
BM = {'source_reconciliation':'actual_working_checkout','database_qualification':'real_postgresql',
      'canonical_writer':'real_collect_ledger','native_staff':'built_installed_staff_apk',
      'native_receiver':'built_installed_receiver_apk','phone_journeys':'physical_carrier_sim_to_ledger',
      'security_acceptance':'independent_security_assessment','recovery_drill':'restoration_and_receiver_replacement'}
MM = {'publisher_and_signing':'verified_publisher_signed_artifact','sms_distribution_route':'authorized_sms_distribution',
      'privacy_and_disclosure':'owner_reviewed_privacy_disclosure','rwanda_and_transfer_applicability':'owner_reviewed_applicability',
      'live_backend_and_model':'real_hosted_backend_and_model','device_sms_lifecycle':'physical_carrier_device_lifecycle',
      'all_views_journeys_accessibility':'installed_screen_and_accessibility','export_and_deletion':'installed_export_and_deletion',
      'security_dependencies':'candidate_security_and_dependency_acceptance','performance_cost':'measured_candidate_performance_and_cost',
      'pilot':'completed_candidate_pilot','store_declarations_if_applicable':'owner_reviewed_store_applicability',
      'backup_recovery':'executed_backup_recovery','support_monitoring':'operational_support_and_monitoring'}

class Rejected(ValueError):
    """Stable error code that does not echo evidence contents or credentials."""

def need(value, code):
    if not value: raise Rejected(code)

def sha(raw): return hashlib.sha256(raw).hexdigest()
def canonical(value): return json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=True,allow_nan=False).encode()
def pretty(value): return (json.dumps(value,sort_keys=True,indent=2,ensure_ascii=True,allow_nan=False)+'\n').encode()
def utcnow(): return dt.datetime.now(UTC).isoformat(timespec='microseconds').replace('+00:00','Z')

def strict_json(raw):
    need(len(raw)<=MAX_JSON,'JSON_TOO_LARGE')
    def pairs(items):
        out={}
        for key,value in items:
            need(key not in out,'DUPLICATE_JSON_KEY');out[key]=value
        return out
    def bad(_): raise Rejected('NONFINITE_JSON_NUMBER')
    try: value=json.loads(raw.decode('utf-8'),object_pairs_hook=pairs,parse_constant=bad)
    except (UnicodeError,json.JSONDecodeError,RecursionError) as exc: raise Rejected('INVALID_JSON') from exc
    need(type(value) is dict,'JSON_OBJECT_REQUIRED')
    return value

def keys(value,expected,code): need(type(value) is dict and set(value)==set(expected),code)
def text(value,code):
    need(type(value) is str and 0<len(value)<=1024 and value.strip()==value and not any(ord(c)<32 or ord(c)==127 for c in value),code)
    return value

def digest(value):
    need(type(value) is str and re.fullmatch('[0-9a-f]{64}',value) is not None,'INVALID_SHA256');return value

def instant(value):
    need(type(value) is str and re.fullmatch(r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?Z',value) is not None,'UTC_TIMESTAMP_REQUIRED')
    try: return dt.datetime.fromisoformat(value[:-1]+'+00:00')
    except ValueError as exc: raise Rejected('INVALID_TIMESTAMP') from exc

def fresh(value,now):
    t=instant(value);need(t<=now,'FUTURE_EVIDENCE');need((now-t).total_seconds()<=MAX_AGE,'STALE_EVIDENCE');return t

def safe_name(name):
    text(name,'INVALID_PATH')
    need(name==unicodedata.normalize('NFC',name),'NONCANONICAL_PATH')
    need(not name.startswith('/') and not any(c in name for c in '\\:<>\"|?*'),'UNSAFE_PATH')
    parts=name.split('/')
    need(all(p not in ('','.','..') and not p.endswith((' ','.')) for p in parts),'UNSAFE_PATH')
    reserved={'CON','PRN','AUX','NUL',*(f'COM{i}' for i in range(1,10)),*(f'LPT{i}' for i in range(1,10))}
    need(all(p.split('.')[0].upper() not in reserved for p in parts),'UNSAFE_PATH')
    return name

def no_links(path):
    absolute=Path(os.path.abspath(path));p=Path(absolute.anchor)
    for part in absolute.parts[1:]:
        p/=part;need(not p.is_symlink(),'SYMLINK_REFUSED')

def read_file(root,name,limit=MAX_FILE):
    safe_name(name);no_links(root);need(root.is_dir(),'ROOT_NOT_DIRECTORY')
    p=root/name;no_links(p)
    need(p.resolve().is_relative_to(root.resolve()),'PATH_ESCAPES_ROOT')
    try:
        a=p.stat(follow_symlinks=False)
        need(stat.S_ISREG(a.st_mode),'NONREGULAR_FILE');need(a.st_nlink==1,'HARDLINK_REFUSED');need(a.st_size<=limit,'FILE_TOO_LARGE')
        fd=os.open(p,os.O_RDONLY|getattr(os,'O_NOFOLLOW',0)|getattr(os,'O_NONBLOCK',0))
        with os.fdopen(fd,'rb') as f:
            b=os.fstat(f.fileno());need(stat.S_ISREG(b.st_mode) and b.st_nlink==1,'NONREGULAR_FILE')
            data=f.read(limit+1);c=os.fstat(f.fileno())
        d=p.stat(follow_symlinks=False)
        sig=lambda s:(s.st_dev,s.st_ino,s.st_size,s.st_mtime_ns,s.st_ctime_ns)
        need(sig(a)==sig(b)==sig(c)==sig(d),'FILE_CHANGED_DURING_READ')
        need(len(data)==d.st_size and len(data)<=limit,'FILE_TOO_LARGE');return data
    except OSError as exc: raise Rejected('FILE_UNAVAILABLE') from exc

def load(path): return strict_json(read_file(path.parent,path.name,MAX_JSON))

def write_new(path,data):
    """Exclusive publication, without overwriting an existing result."""
    no_links(path);path.parent.mkdir(parents=True,exist_ok=True);no_links(path.parent)
    need(not path.exists(),'OUTPUT_EXISTS')
    fd,tmp=tempfile.mkstemp(prefix='.release-write-',dir=path.parent)
    try:
        with os.fdopen(fd,'wb') as f: f.write(data);f.flush();os.fsync(f.fileno())
        try: os.link(tmp,path)
        except FileExistsError as exc: raise Rejected('OUTPUT_EXISTS') from exc
    finally: Path(tmp).unlink(missing_ok=True)

def ref(name,raw): return {'path':safe_name(name),'sha256':sha(raw),'size':len(raw)}

def read_ref(root,item,json_only=False):
    keys(item,{'path','sha256','size'},'INVALID_FILE_REFERENCE');digest(item['sha256'])
    need(type(item['size']) is int and 0<=item['size']<=MAX_FILE,'INVALID_FILE_SIZE')
    raw=read_file(root,item['path'],MAX_JSON if json_only else MAX_FILE)
    need(len(raw)==item['size'] and sha(raw)==item['sha256'],'FILE_HASH_MISMATCH')
    scan(item['path'],raw);return raw

def credential_name(name):
    for p in name.lower().split('/'):
        if p in {'.aws','.ssh','.gnupg','.npmrc','.pypirc','.netrc','local.properties','credentials','credentials.json',
                 'service-account.json','service_account.json','id_rsa','id_ed25519','id_dsa','id_ecdsa'}: return True
        if p.startswith('.env') and p not in {'.env.example','.env.sample','.env.template'}: return True
        if p.endswith(('.jks','.keystore','.pem','.key','.p12','.pfx','.credentials')): return True
    return False

PATTERNS=(
    re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----'),
    re.compile(rb'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b'),
    re.compile(rb'\b(?:ghp_|github_pat_|sb_secret_|sk-proj-)[A-Za-z0-9_\-]{20,}'),
    re.compile(rb'(?i)"type"\s*:\s*"service_account"'),
    re.compile(rb'(?i)(?:https?|postgres(?:ql)?|mysql|redis)://[^\s/:]+:[^\s/@]+@'),
    re.compile(rb'(?i)(?:password|api[_-]?key|access[_-]?token|client[_-]?secret|private[_-]?key|service[_-]?role[_-]?key)'
               rb'[\s\"\']*[:=]\s*[\"\'][A-Za-z0-9+/_=\-]{16,}[\"\']'),
    re.compile(rb'\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b'))

def content_views(raw):
    """Check byte content plus UTF-16/32 text; no content or matches are emitted.

    Heuristic scanning is not a proof of absence. Arbitrarily obfuscated or
    encrypted payloads still require separate security review.
    """
    yield 'bytes', raw
    encodings = []
    if raw.startswith((b'\xff\xfe\x00\x00', b'\x00\x00\xfe\xff')):
        encodings = ['utf-32']
    elif raw.startswith((b'\xff\xfe', b'\xfe\xff')):
        encodings = ['utf-16']
    elif b'\x00' in raw[:4096]:
        # BOM-less encodings occur in exported logs. Only lossless decodes count.
        encodings = ['utf-16-le', 'utf-16-be', 'utf-32-le', 'utf-32-be']
    for encoding in encodings:
        try:
            decoded = raw.decode(encoding).encode('utf-8')
        except UnicodeError:
            continue
        yield encoding, decoded

def content_has_credentials(raw):
    return any(pattern.search(view) for _, view in content_views(raw) for pattern in PATTERNS)

def scan(name,raw,depth=0,budget=None):
    safe_name(name);need(not credential_name(name),'CREDENTIAL_LIKE_FILENAME')
    need(not content_has_credentials(raw),'CREDENTIAL_LIKE_CONTENT')
    suffix=Path(name).suffix.lower()
    if raw.startswith((b'PK\x03\x04',b'PK\x05\x06',b'PK\x07\x08')) or suffix in {'.zip','.jar','.apk','.aab','.xlsx','.docx','.pptx'}:
        return inspect_zip(raw,depth+1,budget)
    need(suffix not in {'.gz','.bz2','.xz','.7z','.rar','.tar','.tgz'} and not raw.startswith((b'\x1f\x8b',b'7z\xbc\xaf',b'Rar!',b'\xfd7zXZ')),'UNSUPPORTED_ARCHIVE')
    return None

def portable_path(name, registry, code):
    """Reject inconsistent case in any shared path component, not just leaves."""
    parts=safe_name(name).split('/')
    for length in range(1,len(parts)+1):
        prefix='/'.join(parts[:length]);key=prefix.casefold()
        need(key not in registry or registry[key]==prefix,code)
        registry[key]=prefix

def source_rows(rows):
    """JSON booleans must not compare equal to integer sizes or modes."""
    need(type(rows) is list and 0<len(rows)<=MAX_ENTRIES,'INVALID_SOURCE_ROWS')
    seen=set();portable={}
    for row in rows:
        keys(row,{'path','sha256','size','executable'},'INVALID_SOURCE_ROW')
        name=safe_name(row['path']);digest(row['sha256'])
        need(type(row['size']) is int and 0<=row['size']<=MAX_FILE,'INVALID_SOURCE_ROW_SIZE')
        need(type(row['executable']) is bool,'INVALID_SOURCE_ROW_EXECUTABLE')
        need(name not in seen,'DUPLICATE_SOURCE_ROW');seen.add(name)
        portable_path(name,portable,'SOURCE_PATH_COLLISION')
    need(rows==sorted(rows,key=lambda row:row['path']),'NONCANONICAL_SOURCE_ROWS')


def inspect_zip(raw,depth=1,budget=None):
    need(depth<=MAX_DEPTH,'ARCHIVE_NESTING_LIMIT');budget=[MAX_TOTAL,MAX_ENTRIES] if budget is None else budget
    entries={};seen=set();portable={}
    try:
        with zipfile.ZipFile(io.BytesIO(raw)) as z:
            need(not content_has_credentials(z.comment),'CREDENTIAL_LIKE_CONTENT')
            need(len(z.infolist())<=budget[1],'ARCHIVE_ENTRY_LIMIT')
            for i in z.infolist():
                budget[1]-=1;need(i.orig_filename==i.filename,'ARCHIVE_FILENAME_TRUNCATED');name=safe_name(i.filename[:-1] if i.is_dir() else i.filename)
                need(name.casefold() not in seen,'DUPLICATE_ARCHIVE_PATH');seen.add(name.casefold())
                portable_path(name,portable,'ARCHIVE_PATH_CASE_COLLISION')
                need(not content_has_credentials(i.comment),'CREDENTIAL_LIKE_CONTENT')
                need(not (stat.S_IMODE(i.external_attr>>16)&0o7000),'ARCHIVE_PRIVILEGED_MODE')
                need(not credential_name(name),'CREDENTIAL_LIKE_FILENAME');kind=stat.S_IFMT(i.external_attr>>16)
                need(kind in {0,stat.S_IFREG,stat.S_IFDIR},'ARCHIVE_SPECIAL_FILE');need(not i.flag_bits&1,'ENCRYPTED_ARCHIVE')
                if i.is_dir():
                    need(kind in {0,stat.S_IFDIR} and i.file_size==0,'ARCHIVE_SPECIAL_FILE');continue
                need(kind!=stat.S_IFDIR,'ARCHIVE_SPECIAL_FILE');need(i.file_size<=MAX_FILE,'ARCHIVE_MEMBER_TOO_LARGE')
                budget[0]-=i.file_size;need(budget[0]>=0,'ARCHIVE_SIZE_LIMIT')
                need(i.file_size<=max(1,i.compress_size)*2000,'ARCHIVE_COMPRESSION_LIMIT')
                with z.open(i) as f: data=f.read(MAX_FILE+1)
                need(len(data)==i.file_size,'ARCHIVE_SIZE_MISMATCH');scan(name,data,depth,budget);entries[name]=data
        files={n.casefold() for n in entries}
        for n in seen:
            parts=n.split('/');need(not any('/'.join(parts[:j]) in files for j in range(1,len(parts))),'ARCHIVE_FILE_DIRECTORY_COLLISION')
    except (zipfile.BadZipFile,RuntimeError,NotImplementedError,EOFError,zlib.error,UnicodeError) as exc: raise Rejected('INVALID_ARCHIVE') from exc
    return entries

def source_entries(root,check_credentials=True):
    no_links(root);need(root.is_dir(),'ROOT_NOT_DIRECTORY');rows=[];seen=set();portable={};total=0
    budget=[MAX_TOTAL,MAX_ENTRIES]
    def walk_error(_):
        # os.walk otherwise ignores unreadable directories and can hash a subset.
        raise Rejected('SOURCE_WALK_FAILED')
    for current,dirs,files in os.walk(root,followlinks=False,onerror=walk_error):
        for d in dirs:
            p=Path(current)/d
            need(not p.is_symlink(),'SYMLINK_REFUSED')
            name=p.relative_to(root).as_posix()
            portable_path(name,portable,'SOURCE_PATH_COLLISION')
        dirs[:]=sorted(d for d in dirs if d not in SKIP)
        for f in sorted(files):
            p=Path(current)/f;name=safe_name(p.relative_to(root).as_posix())
            need(name.casefold() not in seen,'SOURCE_PATH_COLLISION');seen.add(name.casefold())
            portable_path(name,portable,'SOURCE_PATH_COLLISION')
            raw=read_file(root,name)
            total+=len(raw);need(total<=MAX_TOTAL and len(rows)<MAX_ENTRIES,'SOURCE_LIMIT')
            if check_credentials: scan(name,raw,budget=budget)
            rows.append({**ref(name,raw),'executable':bool(p.stat().st_mode&0o111)})
    need(rows,'EMPTY_SOURCE');return sorted(rows,key=lambda r:r['path'])

def capture(root,product,version):
    policy(product,'source');text(version,'INVALID_VERSION');rows=source_entries(root)
    return {'schema_version':SCHEMA,'kind':'source-manifest','product':product,'source_version':version,
            'captured_at':utcnow(),'files':rows,'tree_sha256':sha(canonical(rows)),'excluded_directories':sorted(SKIP)}

def dependencies(source):
    rows=[r for r in source['files'] if Path(r['path']).name in DECLARATIONS or Path(r['path']).name.endswith('.lockfile')
          or re.fullmatch(r'requirements[^/]*\.(txt|lock)',Path(r['path']).name)]
    return {'schema_version':SCHEMA,'kind':'dependency-inventory','product':source['product'],
            'source_version':source['source_version'],'source_tree_sha256':source['tree_sha256'],
            'resolution_status':'unresolved','declarations':rows,'components':[]}

def policy(product,phase):
    need(product in {'BuriMunsi','M-Money','release-safeguards'},'UNKNOWN_PRODUCT')
    need(phase in {'source','build','promotion'},'UNKNOWN_PHASE')
    if phase=='source': requirements={'guard_regression':'local_release_validator_regression'}
    else:
        need(product!='release-safeguards','TOOLING_CANNOT_BE_PRODUCTION')
        requirements={'local_regression':'consolidated_platform_independent','source_reconciliation':'actual_working_checkout',
                      'dependency_resolution':'resolved_runtime_and_build_dependencies'}
        if product=='BuriMunsi': requirements.update(BM)
        if phase=='promotion':
            requirements.update({'signed_distribution':'verified_release_artifacts',
                                 'installed_update':'existing_signed_cloud_packages'} if product=='BuriMunsi'
                                else {**MM,'native_matrix':'pinned_candidate_android_matrix'})
            requirements['operations_authorization']='responsible_owner_authorization'
    return {'validator_version':VERSION,'schema_version':SCHEMA,'product':product,'phase':phase,'max_age_seconds':MAX_AGE,
            'requirements':requirements,'designation':{'source':'source-only','build':'candidate','promotion':'production'}[phase],
            'artifact_ids':([] if phase!='promotion' else ['staff-apk','receiver-apk'] if product=='BuriMunsi' else ['release-apk','release-aab'])}

def policy_sha(product,phase): return sha(canonical(policy(product,phase)))

def validate_consistency(source_root,evidence_root,m,*,product,version,phase,now=None):
    try:
        details=_validate(source_root,evidence_root,m,product,version,phase,now or dt.datetime.now(UTC))
        return {'status':'passed','gate_open':True,'phase':phase,'product':product,'source_version':version,
                'errors':[],'details':details,'production_authorized':False,
                'meaning':'Consistency only; not authenticity, deployment, release authority or independent security certification.'}
    except (Rejected,OSError,TypeError,KeyError,ValueError,RecursionError,OverflowError) as exc:
        return {'status':'blocked','gate_open':False,'phase':phase,'product':product,'source_version':version,
                'production_authorized':False,'errors':[str(exc) if isinstance(exc,Rejected) else 'MALFORMED_OR_UNAVAILABLE_INPUT']}

def validate(source_root,evidence_root,m,*,product,version,phase,now=None,
             trust_policy=None,trust_sha256=None,attestations=None):
    """Public release gate. Non-source application gates require pinned provenance.

    validate_consistency is a diagnostic primitive, not a release gate. Callers
    must protect this code, its runtime, trust-policy hash and CI configuration.
    """
    now=now or dt.datetime.now(UTC)
    result=validate_consistency(source_root,evidence_root,m,product=product,version=version,phase=phase,now=now)
    result['provenance_authenticated']=False
    if not result['gate_open'] or phase=='source':return result
    try:
        need(trust_policy is not None and trust_sha256 is not None,'TRUST_CONFIGURATION_MISSING')
        need(attestations is not None,'PROVENANCE_MISSING')
        import release_provenance
        details=release_provenance.verify(source_root,evidence_root,m,Path(trust_policy),trust_sha256,Path(attestations),now)
        # Catch changes while external signature verification was executing.
        again=validate_consistency(source_root,evidence_root,m,product=product,version=version,phase=phase,now=now)
        need(again['gate_open'],'EVIDENCE_CHANGED_DURING_AUTHENTICATION')
        return {**result,'provenance_authenticated':True,'provenance':details,
                'meaning':'Evidence consistency and configured producer signatures verified; not deployment, independent certification or production authority.'}
    except (Rejected,OSError,TypeError,ValueError,KeyError,ImportError,RecursionError) as exc:
        return {**result,'status':'blocked','gate_open':False,'provenance_authenticated':False,
                'errors':[str(exc) if isinstance(exc,Rejected) else 'PROVENANCE_UNAVAILABLE']}

def verify_installed_update(log, directory, artifacts):
    """Verify the two promoted APKs through the same reader as the native gate."""
    proof = strict_json(log)
    native_scripts = Path(__file__).resolve().parents[1] / 'native/burimunsi/scripts'
    # Import only the installed validator and its siblings, independent of the
    # candidate's source/evidence directories and the caller's Python path.
    program = (
        "import json, sys\n"
        "from pathlib import Path\n"
        "sys.path.insert(0, sys.argv[1])\n"
        "from release_readiness import installed_update\n"
        "installed_update(json.load(sys.stdin), Path(sys.argv[2]), "
        "expected_apks={'staff': sys.argv[3], 'internal_receiver': sys.argv[4]})"
    )
    result = subprocess.run(
        [sys.executable, '-I', '-B', '-c', program, str(native_scripts), str(directory),
         artifacts['staff-apk'], artifacts['receiver-apk']],
        input=canonical(proof), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    need(result.returncode == 0, 'INSTALLED_UPDATE_NOT_VERIFIED')


def _validate(root,eroot,m,product,version,phase,now):
    p=policy(product,phase);text(version,'INVALID_VERSION')
    keys(m,{'schema_version','kind','product','source_version','phase','designation','policy_sha256','run_id','created_at',
            'source_manifest','dependency_inventory','artifacts','qualifications'},'INVALID_MANIFEST_FIELDS')
    need(type(m['schema_version']) is int and m['schema_version']==SCHEMA,'UNSUPPORTED_SCHEMA')
    need(m['kind']=='release-evidence','INVALID_MANIFEST_KIND')
    need(m['product']==product and m['source_version']==version,'SOURCE_IDENTITY_MISMATCH')
    need(m['phase']==phase and m['designation']==p['designation'],'DESIGNATION_NOT_AUTHORIZED')
    need(m['policy_sha256']==policy_sha(product,phase),'POLICY_MISMATCH')
    need(type(m['run_id']) is str and re.fullmatch(r'[a-zA-Z0-9_-]{12,80}',m['run_id']) is not None,'INVALID_RUN_ID')
    created=fresh(m['created_at'],now);sraw=read_ref(eroot,m['source_manifest'],True);s=strict_json(sraw)
    keys(s,{'schema_version','kind','product','source_version','captured_at','files','tree_sha256','excluded_directories'},'INVALID_SOURCE_MANIFEST')
    need(type(s['schema_version']) is int and s['schema_version']==SCHEMA and s['kind']=='source-manifest','UNSUPPORTED_SCHEMA')
    need(s['product']==product and s['source_version']==version,'SOURCE_IDENTITY_MISMATCH')
    captured=fresh(s['captured_at'],now);need(captured<=created,'TIME_ORDER_INVALID')
    need(s['excluded_directories']==sorted(SKIP),'SOURCE_EXCLUSIONS_CHANGED');actual=source_entries(root)
    source_rows(s['files']);need(s['files']==actual,'SOURCE_INVENTORY_MISMATCH');need(digest(s['tree_sha256'])==sha(canonical(actual)),'SOURCE_TREE_MISMATCH')
    d=strict_json(read_ref(eroot,m['dependency_inventory'],True))
    keys(d,{'schema_version','kind','product','source_version','source_tree_sha256','resolution_status','declarations','components'},'INVALID_DEPENDENCY_INVENTORY')
    need(type(d['schema_version']) is int and d['schema_version']==SCHEMA and d['kind']=='dependency-inventory','UNSUPPORTED_SCHEMA')
    need(d['product']==product and d['source_version']==version and d['source_tree_sha256']==s['tree_sha256'],'DEPENDENCY_BINDING_MISMATCH')
    need(canonical(d['declarations'])==canonical(dependencies(s)['declarations']),'DEPENDENCY_DECLARATIONS_MISMATCH')
    need(d['resolution_status'] in {'resolved','unresolved'},'DEPENDENCY_STATUS_INVALID');need(type(d['components']) is list,'INVALID_DEPENDENCY_COMPONENTS')
    if phase!='source': need(d['resolution_status']=='resolved' and len(d['components'])>0,'DEPENDENCIES_UNRESOLVED')
    cids=set()
    for c in d['components']:
        keys(c,{'id','version','artifact'},'INVALID_DEPENDENCY_COMPONENT');cid=text(c['id'],'INVALID_DEPENDENCY_ID');text(c['version'],'INVALID_DEPENDENCY_VERSION')
        need(cid not in cids,'DUPLICATE_DEPENDENCY');cids.add(cid);read_ref(eroot,c['artifact'])
    need(type(m['artifacts']) is list,'INVALID_ARTIFACTS');artifacts={};apaths=set()
    for a in m['artifacts']:
        keys(a,{'id','kind','file'},'INVALID_ARTIFACT');aid=text(a['id'],'INVALID_ARTIFACT_ID');need(aid not in artifacts,'DUPLICATE_ARTIFACT')
        need(a['kind'] in {'apk','aab','report','binary'},'INVALID_ARTIFACT_KIND');raw=read_ref(eroot,a['file']);need(raw,'EMPTY_ARTIFACT')
        path=a['file']['path'];need(path.casefold() not in apaths,'ARTIFACT_PATH_REUSED');apaths.add(path.casefold())
        if a['kind'] in {'apk','aab'}:
            need(path.endswith('.'+a['kind']),'ARTIFACT_KIND_MISMATCH');members=inspect_zip(raw)
            need(('AndroidManifest.xml' if a['kind']=='apk' else 'base/manifest/AndroidManifest.xml') in members,'ANDROID_CONTAINER_INVALID')
        artifacts[aid]=a['file']['sha256']
    for aid in p['artifact_ids']:
        need(aid in artifacts,'REQUIRED_ARTIFACT_MISSING')
        need(next(a['kind'] for a in m['artifacts'] if a['id']==aid)==('aab' if aid.endswith('aab') else 'apk'),'ARTIFACT_KIND_MISMATCH')
    need(type(m['qualifications']) is list,'INVALID_QUALIFICATIONS');qids=set();paths=set();rdigests=set()
    for q in m['qualifications']:
        keys(q,{'id','result'},'INVALID_QUALIFICATION');qid=text(q['id'],'INVALID_QUALIFICATION_ID')
        need(qid not in qids,'DUPLICATE_QUALIFICATION');qids.add(qid);need(qid in p['requirements'],'UNEXPECTED_QUALIFICATION')
        raw=read_ref(eroot,q['result'],True);r=strict_json(raw)
        need(q['result']['path'] not in paths and sha(raw) not in rdigests,'REUSED_QUALIFICATION_RESULT');paths.add(q['result']['path']);rdigests.add(sha(raw))
        keys(r,{'schema_version','kind','id','scope','product','source_version','run_id','policy_sha256','source_tree_sha256',
                'source_manifest_sha256','dependency_inventory_sha256','artifact_sha256s','started_at','completed_at',
                'status','executed','exit_code','counts','command','log'},'INVALID_RESULT_FIELDS')
        need(type(r['schema_version']) is int and r['schema_version']==SCHEMA and r['kind']=='qualification-result','UNSUPPORTED_SCHEMA')
        need(r['id']==qid and r['scope']==p['requirements'][qid],'QUALIFICATION_SCOPE_MISMATCH')
        need(r['product']==product and r['source_version']==version and r['run_id']==m['run_id'] and r['policy_sha256']==m['policy_sha256'],'RESULT_IDENTITY_MISMATCH')
        need(r['source_tree_sha256']==s['tree_sha256'] and r['source_manifest_sha256']==sha(sraw)
             and r['dependency_inventory_sha256']==m['dependency_inventory']['sha256'],'RESULT_SOURCE_BINDING_MISMATCH')
        need(r['artifact_sha256s']==artifacts,'RESULT_ARTIFACT_BINDING_MISMATCH')
        started=fresh(r['started_at'],now);ended=fresh(r['completed_at'],now);need(captured<=started<=ended<=created,'TIME_ORDER_INVALID')
        need(r['status']=='passed' and r['executed'] is True,'QUALIFICATION_NOT_EXECUTED_OR_NOT_PASSED')
        need(type(r['exit_code']) is int and r['exit_code']==0,'QUALIFICATION_EXIT_CODE')
        keys(r['counts'],{'executed','failed','skipped','blocked'},'INVALID_RESULT_COUNTS')
        need(all(type(v) is int and v>=0 for v in r['counts'].values()),'INVALID_RESULT_COUNTS')
        need(r['counts']['executed']>0 and all(r['counts'][k]==0 for k in ('failed','skipped','blocked')),'INCOMPLETE_QUALIFICATION')
        need(type(r['command']) is list and len(r['command'])>0,'RESULT_COMMAND_MISSING')
        for arg in r['command']: text(arg,'INVALID_COMMAND_ARGUMENT')
        log=read_ref(eroot,r['log']);need(log.strip(),'EMPTY_TEST_LOG');need(r['log']['path'] not in paths,'REUSED_QUALIFICATION_LOG');paths.add(r['log']['path'])
        if qid == 'installed_update':
            verify_installed_update(log, (eroot / r['log']['path']).parent, artifacts)
    need(qids==set(p['requirements']),'MISSING_QUALIFICATION_RESULTS')
    evidence_references(m,lambda item:read_ref(eroot,item,True))
    return {'source_tree_sha256':s['tree_sha256'],'source_files':len(actual),'qualification_count':len(qids),
            'artifact_sha256s':artifacts,'dependency_resolution':d['resolution_status'],'policy_sha256':m['policy_sha256']}

def evidence_references(m,read_json):
    """Exact transitive evidence closure; one portable path per evidence role."""
    refs=[m['source_manifest'],m['dependency_inventory']]+[a['file'] for a in m['artifacts']]
    for q in m['qualifications']:
        refs.extend([q['result'],strict_json(read_json(q['result']))['log']])
    d=strict_json(read_json(m['dependency_inventory']))
    refs.extend(c['artifact'] for c in d['components'])
    seen={'release-manifest.json'};portable={}
    for item in refs:
        keys(item,{'path','sha256','size'},'INVALID_FILE_REFERENCE')
        name=safe_name(item['path']);digest(item['sha256'])
        need(type(item['size']) is int and 0<=item['size']<=MAX_FILE,'INVALID_FILE_SIZE')
        need(name.casefold() not in seen,'EVIDENCE_PATH_REUSED');seen.add(name.casefold())
        portable_path(name,portable,'EVIDENCE_PATH_CASE_COLLISION')
    return refs

def package(root,eroot,m,product,version,output):
    no_links(output);out=output.absolute()
    need(not out.is_relative_to(root.resolve()) and not out.is_relative_to(eroot.resolve()),'OUTPUT_ALIASES_INPUT')
    result=validate(root,eroot,m,product=product,version=version,phase='source')
    need(result['gate_open'],'SOURCE_PACKAGE_GATE_CLOSED:'+','.join(result['errors']))
    s=strict_json(read_ref(eroot,m['source_manifest'],True));entries={};modes={}
    for row in s['files']:
        raw=read_file(root,row['path']);need(sha(raw)==row['sha256'] and len(raw)==row['size'],'SOURCE_CHANGED_DURING_PACKAGE')
        name='source/'+row['path'];entries[name]=raw;modes[name]=0o755 if row['executable'] else 0o644
    refs=[m['source_manifest'],m['dependency_inventory']]+[a['file'] for a in m['artifacts']]
    for q in m['qualifications']: refs.extend([q['result'],strict_json(read_ref(eroot,q['result'],True))['log']])
    d=strict_json(read_ref(eroot,m['dependency_inventory'],True));refs.extend(c['artifact'] for c in d['components'])
    for item in refs:
        name='evidence/'+item['path'];raw=read_ref(eroot,item)
        need(name not in entries or entries[name]==raw,'PACKAGE_REFERENCE_COLLISION');entries[name]=raw
    need('evidence/release-manifest.json' not in entries,'PACKAGE_REFERENCE_COLLISION');entries['evidence/release-manifest.json']=pretty(m)
    meta={'schema_version':SCHEMA,'kind':'source-package','designation':'source-only','product':product,'source_version':version,
          'source_tree_sha256':s['tree_sha256'],'production_authorized':False,
          'files':[{**ref(n,entries[n]),'mode':modes.get(n,0o644)} for n in sorted(entries)]}
    entries['PACKAGE-MANIFEST.json']=pretty(meta)
    need(validate(root,eroot,m,product=product,version=version,phase='source')['gate_open'],'INPUTS_CHANGED_DURING_PACKAGE')
    raw=zip_bytes(entries,modes);audit_package(raw);write_new(output,raw)
    return {'status':'passed','designation':'source-only','sha256':sha(raw),'size':len(raw),'files':len(entries),'production_authorized':False}

def zip_bytes(entries,modes=None):
    buf=io.BytesIO();modes=modes or {}
    with zipfile.ZipFile(buf,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for name,raw in sorted(entries.items()):
            i=zipfile.ZipInfo(name,(1980,1,1,0,0,0));i.create_system=3;i.external_attr=(stat.S_IFREG|modes.get(name,0o644))<<16
            i.compress_type=zipfile.ZIP_DEFLATED;z.writestr(i,raw)
    return buf.getvalue()

def audit_package(raw):
    entries=inspect_zip(raw);need('PACKAGE-MANIFEST.json' in entries,'PACKAGE_MANIFEST_MISSING');p=strict_json(entries['PACKAGE-MANIFEST.json'])
    keys(p,{'schema_version','kind','designation','product','source_version','source_tree_sha256','production_authorized','files'},'INVALID_PACKAGE_MANIFEST')
    need(type(p['schema_version']) is int and p['schema_version']==SCHEMA,'UNSUPPORTED_SCHEMA')
    need(p['kind']=='source-package' and p['designation']=='source-only' and p['production_authorized'] is False,'DESIGNATION_NOT_AUTHORIZED')
    with zipfile.ZipFile(io.BytesIO(raw)) as z: modes={i.filename:stat.S_IMODE(i.external_attr>>16) for i in z.infolist()}
    need(canonical(p['files'])==canonical([{**ref(n,entries[n]),'mode':modes[n]} for n in sorted(entries) if n!='PACKAGE-MANIFEST.json']),'PACKAGE_INVENTORY_MISMATCH')
    m=strict_json(entries.get('evidence/release-manifest.json',b'{}'))
    need(m.get('phase')=='source' and m.get('designation')=='source-only','DESIGNATION_NOT_AUTHORIZED')
    need(m.get('product')==p['product'] and m.get('source_version')==p['source_version'],'PACKAGE_IDENTITY_MISMATCH')
    sr=m.get('source_manifest',{});sraw=entries.get('evidence/'+safe_name(sr.get('path')),b'')
    need(ref(sr['path'],sraw)==sr,'SOURCE_MANIFEST_HASH_MISMATCH');s=strict_json(sraw)
    source_rows(s['files'])
    need(p['source_tree_sha256']==s.get('tree_sha256')==sha(canonical(s.get('files'))),'SOURCE_TREE_MISMATCH')
    src={n[7:]:b for n,b in entries.items() if n.startswith('source/')}
    need(set(src)=={r['path'] for r in s['files']},'PACKAGE_SOURCE_INVENTORY_MISMATCH')
    for r in s['files']:
        need(ref(r['path'],src[r['path']])=={k:r[k] for k in ('path','sha256','size')},'PACKAGE_SOURCE_HASH_MISMATCH')
        need(modes['source/'+r['path']]==(0o755 if r['executable'] else 0o644),'PACKAGE_SOURCE_MODE_MISMATCH')
    def from_package(item):
        name='evidence/'+safe_name(item['path'])
        need(name in entries,'PACKAGE_EVIDENCE_MISSING')
        value=entries[name]
        need(ref(item['path'],value)==item,'PACKAGE_EVIDENCE_HASH_MISMATCH')
        return value
    refs=evidence_references(m,from_package)
    for item in refs: from_package(item)
    expected={'PACKAGE-MANIFEST.json','evidence/release-manifest.json'} | {'source/'+n for n in src} | {'evidence/'+r['path'] for r in refs}
    need(set(entries)==expected,'PACKAGE_UNDECLARED_PAYLOAD')
    return {'status':'passed','designation':'source-only','sha256':sha(raw),'files':len(entries),
            'meaning':'Byte integrity and reference closure only; use verify-package for fresh qualification checks.'}

def verify_package(raw,*,product,version,expected_sha256,now=None):
    """Verify source-package freshness without executing any packaged source code.

    The caller must use an independently obtained expected hash. This binding
    check does not authenticate who produced the evidence or authorize release.
    Temporary files are created only after archive inspection and exact closure.
    """
    need(sha(raw)==digest(expected_sha256),'ARCHIVE_HASH_MISMATCH')
    audit_package(raw);entries=inspect_zip(raw)
    with zipfile.ZipFile(io.BytesIO(raw)) as z:
        modes={i.filename:stat.S_IMODE(i.external_attr>>16) for i in z.infolist()}
    with tempfile.TemporaryDirectory(prefix='release-verify-') as tmp:
        base=Path(tmp)
        for name,data in entries.items():
            path=base/name;path.parent.mkdir(parents=True,exist_ok=True)
            path.write_bytes(data);path.chmod(modes[name])
        result=validate(base/'source',base/'evidence',strict_json(entries['evidence/release-manifest.json']),
                        product=product,version=version,phase='source',now=now)
    return {**result,'archive_sha256':sha(raw),'packaged_code_executed':False,
            'provenance_authenticated':False}

def main(argv=None):
    ap=argparse.ArgumentParser(description=__doc__);sub=ap.add_subparsers(dest='action',required=True)
    for action in ('capture','validate','package'):
        c=sub.add_parser(action);c.add_argument('--source',type=Path,required=True);c.add_argument('--product',required=True);c.add_argument('--version',required=True)
        if action!='capture': c.add_argument('--evidence-root',type=Path,required=True);c.add_argument('--manifest',type=Path,required=True)
        if action=='validate':
            c.add_argument('--phase',choices=['source','build','promotion'],required=True)
            c.add_argument('--trust-policy',type=Path);c.add_argument('--trust-sha256');c.add_argument('--attestations',type=Path)
        else: c.add_argument('--output',type=Path,required=True)
    a=sub.add_parser('audit-package');a.add_argument('archive',type=Path)
    v=sub.add_parser('verify-package');v.add_argument('archive',type=Path);v.add_argument('--product',required=True)
    v.add_argument('--version',required=True);v.add_argument('--sha256',required=True)
    args=ap.parse_args(argv)
    try:
        if args.action=='capture':
            need(not args.output.absolute().is_relative_to(args.source.resolve()),'OUTPUT_ALIASES_INPUT')
            value=capture(args.source,args.product,args.version);write_new(args.output,pretty(value));result={'status':'captured','files':len(value['files']),'tree_sha256':value['tree_sha256']}
        elif args.action=='audit-package': result=audit_package(read_file(args.archive.parent,args.archive.name))
        elif args.action=='verify-package': result=verify_package(read_file(args.archive.parent,args.archive.name),product=args.product,version=args.version,expected_sha256=args.sha256)
        elif args.action=='validate': result=validate(args.source,args.evidence_root,load(args.manifest),product=args.product,version=args.version,phase=args.phase,trust_policy=args.trust_policy,trust_sha256=args.trust_sha256,attestations=args.attestations)
        else: result=package(args.source,args.evidence_root,load(args.manifest),args.product,args.version,args.output)
        print(json.dumps(result,sort_keys=True));return 2 if result['status']=='blocked' else 0
    except (Rejected,OSError,ValueError,TypeError,KeyError,RecursionError) as exc:
        print(json.dumps({'status':'blocked','gate_open':False,'production_authorized':False,
                          'errors':[str(exc) if isinstance(exc,Rejected) else 'MALFORMED_OR_UNAVAILABLE_INPUT']}));return 2

if __name__=='__main__': raise SystemExit(main())
