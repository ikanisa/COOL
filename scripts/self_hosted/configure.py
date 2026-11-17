"""Validate private provider settings and project them into exact service scopes.

This changes files only. It never enables a Cron job, makes a provider request,
starts a container, or replaces signing/data/session keys.
"""
from __future__ import annotations
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import time
sys.dont_write_bytecode=True
from urllib.parse import urlsplit
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from scripts.self_hosted.prepare import PROVIDER_SETTINGS,PRIVATE_FEATURE_CONTROLS,CANONICAL_SCHEDULER_CONTROLS,dotenv,seal_configuration,CONFIGURATION_FILES,AUTH_PRIVATE_PROVIDER_FIELDS
from scripts.supabase.deployment_profile import profile_sha256,canonical_profile

# Public fixtures documented by Cloudflare, never production credentials.
# https://developers.cloudflare.com/turnstile/troubleshooting/testing/
TURNSTILE_TEST_SITE_KEYS=frozenset((
    '1x00000000000000000000AA','2x00000000000000000000AB',
    '1x00000000000000000000BB','2x00000000000000000000BB',
    '3x00000000000000000000FF',
))
TURNSTILE_TEST_SECRET_KEYS=frozenset((
    '1x0000000000000000000000000000000AA',
    '2x0000000000000000000000000000000AA',
    '3x0000000000000000000000000000000AA',
))

# Accommodates the existing per-field character contract even when JSON encodes
# every non-BMP code point as a surrogate pair, while bounding a hostile file.
MAX_PROVIDER_SETTINGS_BYTES=32*1024*1024
MAX_PROVIDER_FIELD_CHARS=32768
MAX_FCM_ACCOUNT_BYTES=16384
NATIVE_CONTROLS={'BURIMUNSI_NATIVE_ENABLED':'false','BURIMUNSI_NATIVE_WORKERS_ENABLED':'false',
                 'BURIMUNSI_NATIVE_UPLOADS_ENABLED':'false','BURIMUNSI_COLLECTION_ID':''}
NATIVE_PRIVATE_KEYS=('BURIMUNSI_PIN_PEPPER_BASE64','BURIMUNSI_PIN_PEPPER_ID','BURIMUNSI_CURSOR_KEY_BASE64')
INGRESS_CONTROLS={'COLLECT_NATIVE_INGRESS_EDGE_PROOF_JSON':'','COLLECT_NATIVE_INGRESS_EDGE_PROOF_SHA256':''}
INGRESS_PRIVATE_KEYS=('COLLECT_NATIVE_INGRESS_KEY_BASE64','COLLECT_NATIVE_INGRESS_KEY_ID')
ADMIN_EMAIL_OTP_CONTROLS={'COLLECT_ADMIN_EMAIL_OTP_TTL_SECONDS':'1800'}

def native_unique_pairs(pairs):
    result={}
    for name,value in pairs:
        if name in result:raise ValueError('Protected native key configuration is invalid')
        result[name]=value
    return result

def native_defaults(settings):
    # The six new switches are individually optional and default off. Apart
    # from those additions, retain only the reviewed previous contract shapes.
    # No key file or provider-settings file is rewritten by normalization.
    if isinstance(settings,dict):
        missing=set(PROVIDER_SETTINGS)-set(settings)
        previous_native=set(NATIVE_CONTROLS)-{'BURIMUNSI_NATIVE_UPLOADS_ENABLED'}
        previous_shapes=(set(),previous_native,set(INGRESS_CONTROLS),previous_native|set(INGRESS_CONTROLS))
        allowed=tuple(shape|new|email for shape in previous_shapes
                      for new in (set(),{'BURIMUNSI_NATIVE_UPLOADS_ENABLED'})
                      for email in (set(),set(ADMIN_EMAIL_OTP_CONTROLS)))
        previous_missing=missing-set(PRIVATE_FEATURE_CONTROLS)-set(CANONICAL_SCHEDULER_CONTROLS)
        if set(settings)<=set(PROVIDER_SETTINGS) and previous_missing in allowed:
            defaults={**NATIVE_CONTROLS,**INGRESS_CONTROLS,**ADMIN_EMAIL_OTP_CONTROLS,**PRIVATE_FEATURE_CONTROLS,**CANONICAL_SCHEDULER_CONTROLS}
            return {**settings,**{key:defaults[key] for key in missing}}
    return settings

def admin_email_otp_ttl(settings):
    value=settings.get('COLLECT_ADMIN_EMAIL_OTP_TTL_SECONDS')
    if not isinstance(value,str) or not re.fullmatch(r'[1-9][0-9]{1,3}',value) or not 60<=int(value)<=1800:
        raise ValueError('Admin email OTP lifetime must be 60 to 1800 seconds')
    return int(value)

def native_key(value,minimum=32,maximum=32):
    decoded=None
    try:
        if isinstance(value,str) and 44<=len(value)<=344 and len(value)%4==0:
            candidate=base64.b64decode(value,validate=True)
            if minimum<=len(candidate)<=maximum and base64.b64encode(candidate).decode('ascii')==value:decoded=candidate
    except (ValueError,TypeError):pass
    if decoded is None:raise ValueError('Protected native key configuration is invalid')
    return decoded

def protected_private_keys(release):
    path=release/'private/keys.json';keys={}
    if path.exists() or path.is_symlink():
        private_file(path)
        parsed=None
        try:
            with path.open('rb') as source:raw=source.read(131073)
            if len(raw)<=131072:parsed=json.loads(raw.decode('utf8'),object_pairs_hook=native_unique_pairs)
        except (ValueError,RecursionError):pass
        if not isinstance(parsed,dict):raise ValueError('Protected native key configuration is invalid')
        keys=parsed
    return keys

def native_private_configuration(release,settings,functions,stack):
    keys=protected_private_keys(release)
    present=[name in keys for name in NATIVE_PRIVATE_KEYS]
    enabled=settings['BURIMUNSI_NATIVE_ENABLED']=='true'
    if not any(present):
        if enabled or any(name in values for name in NATIVE_PRIVATE_KEYS for values in (functions,stack)):
            raise ValueError('Protected native keys require explicit retained-key provisioning')
        return {}
    if not all(present):raise ValueError('Protected native key configuration is incomplete')
    native={name:keys[name] for name in NATIVE_PRIVATE_KEYS}
    pepper=native_key(native['BURIMUNSI_PIN_PEPPER_BASE64'],32,256)
    cursor=native_key(native['BURIMUNSI_CURSOR_KEY_BASE64'])
    if not isinstance(native['BURIMUNSI_PIN_PEPPER_ID'],str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._:-]{0,127}',native['BURIMUNSI_PIN_PEPPER_ID']):
        raise ValueError('Protected native pepper identity is invalid')
    if pepper==cursor:raise ValueError('Native credential and cursor key purposes must be independent')
    domains=[set(),set()]
    for values in (keys,functions,stack):
        for name in NATIVE_PRIVATE_KEYS:
            if name in values and values[name]!=native[name]:raise ValueError('Retained native key identity changed; no automatic rotation')
        for index,name in enumerate(('DATA_ENCRYPTION_KEY','SESSION_ENCRYPTION_KEY')):
            if name in values:domains[index].add(native_key(values[name]))
        for index,name in enumerate(('DATA_DECRYPTION_KEYS_JSON','SESSION_DECRYPTION_KEYS_JSON')):
            if values.get(name) in (None,''):continue
            ring=None
            try:ring=json.loads(values[name],object_pairs_hook=native_unique_pairs)
            except (ValueError,TypeError,RecursionError):pass
            if not isinstance(ring,dict) or len(ring)>8:raise ValueError('Protected native key separation is unavailable')
            domains[index].update(native_key(value) for value in ring.values())
    if any(value in (pepper,cursor) for domain in domains for value in domain):
        raise ValueError('Native keys cannot reuse DATA or BFF key material')
    if enabled and (not all(domains) or domains[0]&domains[1]):
        raise ValueError('Native activation requires independent existing DATA and BFF key purposes')
    return native

def ingress_private_configuration(release,settings,functions,stack,*,keys=None):
    if keys is None:keys=protected_private_keys(release)
    present=[name in keys for name in INGRESS_PRIVATE_KEYS]
    if not any(present):
        if settings['BURIMUNSI_NATIVE_ENABLED']=='true' or any(name in values for name in INGRESS_PRIVATE_KEYS for values in (functions,stack)):
            raise ValueError('Protected ingress keys require explicit retained-key provisioning')
        return {}
    if not all(present):raise ValueError('Protected ingress key configuration is incomplete')
    chosen={name:keys[name] for name in INGRESS_PRIVATE_KEYS};material=native_key(chosen['COLLECT_NATIVE_INGRESS_KEY_BASE64'])
    if not isinstance(chosen['COLLECT_NATIVE_INGRESS_KEY_ID'],str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._:-]{0,127}',chosen['COLLECT_NATIVE_INGRESS_KEY_ID']):
        raise ValueError('Protected ingress identity is invalid')
    for values in (keys,functions,stack):
        for name in INGRESS_PRIVATE_KEYS:
            if name in values and values[name]!=chosen[name]:raise ValueError('Retained ingress key identity changed; no automatic rotation')
        for name in ('DATA_ENCRYPTION_KEY','SESSION_ENCRYPTION_KEY','BURIMUNSI_PIN_PEPPER_BASE64','BURIMUNSI_CURSOR_KEY_BASE64'):
            if values.get(name) and native_key(values[name],32,256)==material:raise ValueError('Ingress keys require independent protected purposes')
        for name in ('DATA_DECRYPTION_KEYS_JSON','SESSION_DECRYPTION_KEYS_JSON'):
            if not values.get(name):continue
            ring=None
            try:ring=json.loads(values[name],object_pairs_hook=native_unique_pairs)
            except (ValueError,TypeError,RecursionError):pass
            if not isinstance(ring,dict) or len(ring)>8:raise ValueError('Protected ingress key separation is unavailable')
            if any(native_key(value)==material for value in ring.values()):raise ValueError('Ingress keys require independent protected purposes')
    return chosen

def validate_ingress_proof(settings,profile):
    raw=settings['COLLECT_NATIVE_INGRESS_EDGE_PROOF_JSON'];digest=settings['COLLECT_NATIVE_INGRESS_EDGE_PROOF_SHA256']
    if not raw and not digest:
        if settings['BURIMUNSI_NATIVE_ENABLED']=='true':raise ValueError('Reviewed native ingress edge proof required')
        return False
    proof=None
    try:proof=json.loads(raw,object_pairs_hook=native_unique_pairs)
    except (ValueError,TypeError,RecursionError):pass
    legacy=isinstance(proof,dict) and proof.get('format')=='collect.native-ingress.edge-proof.v1'
    fields={'directTunnelOnly','evidenceSha256','format','profileSha256','protectedUnixSocket','pseudoIpv4',
            'reviewedAt','status','supabaseOrigin','tunnelId'}
    fields.update({'expiresAt','nativeWorkerGuardExpression','nativeWorkerGuardRuleId'} if legacy else {'nativeWorkerGuard'})
    now=int(time.time()*1000);host=urlsplit(profile['supabase_origin']).hostname
    expression='(http.host eq "'+host+'" and starts_with(http.request.uri.path, "/functions/v1/collect-api/v1/burimunsi") and cf.worker.upstream_zone ne "")'
    valid=(isinstance(proof,dict) and set(proof)==fields and json.dumps(proof,sort_keys=True,separators=(',',':'))==raw and
        re.fullmatch(r'[a-f0-9]{64}',digest or '') and hashlib.sha256(raw.encode()).hexdigest()==digest and
        proof['format'] in ('collect.native-ingress.edge-proof.v1','collect.native-ingress.edge-proof.v2') and proof['status']=='reviewed' and
        proof['profileSha256']==profile_sha256(profile) and proof['supabaseOrigin']==profile['supabase_origin'] and
        isinstance(proof['tunnelId'],str) and re.fullmatch(r'[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}',proof['tunnelId']) and
        proof['directTunnelOnly'] is True and proof['protectedUnixSocket'] is True and
        proof['pseudoIpv4']=='off' and isinstance(proof['evidenceSha256'],str) and re.fullmatch(r'[a-f0-9]{64}',proof['evidenceSha256']) and
        type(proof['reviewedAt']) is int and 0<proof['reviewedAt']<=now)
    if valid:
        valid=(isinstance(proof['nativeWorkerGuardRuleId'],str) and re.fullmatch(r'[a-f0-9]{32}',proof['nativeWorkerGuardRuleId']) and
               proof['nativeWorkerGuardExpression']==expression and type(proof['expiresAt']) is int and
               0<proof['expiresAt']-proof['reviewedAt']<=7*86400000) if legacy else proof['nativeWorkerGuard']=='origin_cf_worker_presence_reject'
    # Configuration review is provenance, not a renewable Auth credential. The
    # legacy expiry remains in its original record; it cannot stop requests.
    # Real request attestations retain their independent 30-second HMAC TTL.
    if not valid:raise ValueError('Reviewed native ingress edge proof is invalid')
    return True

def provider_utf8(value):
    """Enforce the projection contract without leaking an encoding error."""
    encoded=None
    try:
        if isinstance(value,str) and len(value)<=MAX_PROVIDER_FIELD_CHARS:
            # Use the same character rules as the environment-file writer.
            dotenv({'VALUE':value})
            encoded=value.encode('utf8')
    except ValueError:pass
    if encoded is None:raise ValueError('Provider settings could not be parsed')
    return encoded

def read_provider_settings(path):
    """Read bounded UTF-8 JSON without exposing malformed private input."""
    with path.open('rb') as source:raw=source.read(MAX_PROVIDER_SETTINGS_BYTES+1)
    settings=None
    try:
        if len(raw)<=MAX_PROVIDER_SETTINGS_BYTES:
            settings=json.loads(raw.decode('utf8'))
    except (ValueError,RecursionError):pass
    raw=None
    if not isinstance(settings,dict) or any(not isinstance(value,str) for value in settings.values()):
        settings=None
        raise ValueError('Provider settings could not be parsed')
    valid=True
    try:
        for key,value in settings.items():
            provider_utf8(key)
            provider_utf8(value)
    except ValueError:valid=False
    key=value=None
    if not valid:
        settings=None
        raise ValueError('Provider settings could not be parsed: invalid environment entry')
    return native_defaults(settings)

def parse_fcm_account_json(value):
    """Parse the member service account without retaining a decoder error."""
    # Each UTF-8 code point occupies at least one byte. Avoid allocating a
    # larger encoded copy when the existing byte limit cannot be met.
    if not isinstance(value,str) or len(value)>MAX_FCM_ACCOUNT_BYTES:
        raise ValueError('Provider settings could not be parsed')
    encoded=provider_utf8(value)
    if len(encoded)>MAX_FCM_ACCOUNT_BYTES:
        encoded=None
        raise ValueError('Provider settings could not be parsed')
    account=None
    try:account=json.loads(value)
    except (ValueError,RecursionError):pass
    encoded=None
    if not isinstance(account,dict):
        account=None
        raise ValueError('Provider settings could not be parsed')
    return account

def verify_configuration(release):
    path=release/'private/configuration.json';private_file(path)
    receipt=json.loads(path.read_text());meta=json.loads((release/'release.json').read_text())
    if set(receipt)!={'format','profile_sha256','source_sha256','files'} or receipt['format']!='collect.selfhost.configuration.v1' or receipt['profile_sha256']!=meta['profile_sha256'] or receipt['source_sha256']!=meta['source_sha256'] or set(receipt['files'])!=set(CONFIGURATION_FILES):raise ValueError('Exact configured release receipt required')
    import hashlib
    if any(hashlib.sha256((release/name).read_bytes()).hexdigest()!=digest for name,digest in receipt['files'].items()):raise ValueError('Configuration changed or projection was interrupted; configure before operating')

def read_env(path):
    return parse_env(path.read_text(encoding='utf8'))

def parse_env(text):
    values={}
    lines=text.split('\n')
    if lines[-1]=='':lines.pop()
    # splitlines() also splits valid Unicode characters inside quoted values.
    for line in lines:
        key,sep,raw=line.partition('=')
        if not sep or key in values or not re.fullmatch(r'[A-Z][A-Z0-9_]*',key):raise ValueError('Invalid generated environment file')
        values[key]=json.loads(raw).replace('$$','$')
    return values

def private_file(path):
    info=path.lstat()
    if path.is_symlink() or not path.is_file() or info.st_nlink!=1 or info.st_mode&0o077 or info.st_uid!=os.getuid():
        raise ValueError('Private settings require an owned mode0600 regular file')

def fcm_identity(project,email,key):
    if any(not isinstance(value,str) for value in (project,email,key)):return False
    return (bool(re.fullmatch(r'[a-z][a-z0-9-]{4,28}[a-z0-9]',project))
        and bool(re.fullmatch(r'[A-Za-z0-9._-]+@'+re.escape(project)+r'\.iam\.gserviceaccount\.com',email))
        and len(key)<=8192 and bool(re.fullmatch(r'-----BEGIN PRIVATE KEY-----\r?\n[A-Za-z0-9+/=\r\n]+-----END PRIVATE KEY-----\r?\n?',key)))

def native_jpeg_ocr_configuration(settings,source_sha,*,now=None):
    """Admit only the declared in-process JPEG preview using existing OpenAI bindings.

    This validates owner feature authorization and technical pins. It does not
    assert a separate legal assessment or send an image to any provider.
    """
    enabled=settings.get('BURIMUNSI_SMART_ONBOARDING_ADVANCED_ENABLED')=='true'
    raw=settings.get('ROSTER_AI_APPROVAL_JSON','')
    approval_sha=settings.get('ROSTER_AI_APPROVAL_SHA256','')
    if not enabled:
        if raw or approval_sha:
            raise ValueError('Roster OCR requires explicit native JPEG feature enablement')
        return False
    error='Source-bound owner-authorized native JPEG OCR configuration required'
    try:
        if (settings.get('BURIMUNSI_NATIVE_ENABLED')!='true' or
            settings.get('ROSTER_DECODER_PROTOCOL')!='collect-native-jpeg-v1' or
            settings.get('ROSTER_DECODER_URL')!='urn:collect:decoder:native-jpeg:v1' or
            settings.get('ROSTER_DECODER_SECRET')!='' or
            not re.fullmatch(r'[a-f0-9]{64}',settings.get('ROSTER_DECODER_BUILD_SHA256','')) or
            not isinstance(raw,str) or len(raw)>16384 or
            hashlib.sha256(raw.encode('utf8')).hexdigest()!=approval_sha):
            raise ValueError(error)
        policy=json.loads(raw,object_pairs_hook=native_unique_pairs)
        required={'schema_version','status','enabled','purpose','provider','responses_endpoint',
            'decoder_protocol','decoder_identity','decoder_build_sha256','model','collection_id',
            'source_sha256','authorization_evidence_sha256','technical_checks_sha256','authorized_at',
            'valid_until','request_consent_required','preview_only'}
        if (not isinstance(policy,dict) or set(policy)!=required or
            json.dumps(policy,ensure_ascii=False,separators=(',',':'))!=raw or
            type(policy['schema_version']) is not int or policy['schema_version']!=2 or
            policy['status']!='owner_authorized' or policy['enabled'] is not True or
            policy['purpose']!='collect_roster_static_jpeg_preview' or policy['provider']!='openai' or
            policy['responses_endpoint']!='https://api.openai.com/v1/responses' or
            policy['decoder_protocol']!=settings['ROSTER_DECODER_PROTOCOL'] or
            policy['decoder_identity']!=settings['ROSTER_DECODER_URL'] or
            policy['decoder_build_sha256']!=settings['ROSTER_DECODER_BUILD_SHA256'] or
            policy['source_sha256']!=source_sha or not re.fullmatch(r'[a-f0-9]{64}',source_sha) or
            any(not isinstance(policy[key],str) or not re.fullmatch(r'[a-f0-9]{64}',policy[key])
                for key in ('authorization_evidence_sha256','technical_checks_sha256')) or
            not isinstance(policy['model'],str) or
            not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._:-]{0,127}',policy['model']) or
            policy['model']!=settings.get('ROSTER_AI_MODEL') or policy['model']!=settings.get('MOMO_AI_MODEL') or
            len(settings.get('OPENAI_API_KEY',''))<20 or
            not isinstance(policy['collection_id'],str) or
            not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]{0,127}',policy['collection_id']) or
            policy['request_consent_required'] is not True or policy['preview_only'] is not True):
            raise ValueError(error)
        scopes=[settings.get(key) for key in ('BURIMUNSI_COLLECTION_ID','BURIMUNSI_CANONICAL_SCHEDULER_COLLECTION_ID')
                if settings.get(key)]
        # Empty rollout filters retain authenticated-grant scope resolution.
        # The explicit owner-policy collection is checked on every request.
        if any(scope!=policy['collection_id'] for scope in scopes):raise ValueError(error)
        # ISO timestamps mirror the runtime policy; no invented expiry is required.
        from datetime import datetime,timezone
        def timestamp(value):
            if not isinstance(value,str):raise ValueError(error)
            parsed=datetime.fromisoformat(value.replace('Z','+00:00'))
            if parsed.tzinfo is None:raise ValueError(error)
            return parsed.astimezone(timezone.utc).timestamp()
        start=timestamp(policy['authorized_at'])
        end=float('inf') if policy['valid_until'] is None else timestamp(policy['valid_until'])
        current=time.time() if now is None else now
        if not start<=current<end:raise ValueError(error)
        return True
    except (ValueError,TypeError,KeyError,RecursionError,OverflowError) as exc:
        raise ValueError(error) from exc

def validated_settings(settings,profile,source_sha):
    settings=native_defaults(settings)
    if not isinstance(settings,dict) or set(settings)!=set(PROVIDER_SETTINGS) or any(not isinstance(v,str) or '\0' in v or len(v)>MAX_PROVIDER_FIELD_CHARS for v in settings.values()):raise ValueError('Exact provider settings contract required')
    for value in settings.values():provider_utf8(value)
    flags=[k for k,v in PROVIDER_SETTINGS.items() if v in ('true','false')]
    if any(settings[k] not in ('true','false') for k in flags):raise ValueError('Provider switches require true or false')
    if settings['BURIMUNSI_NATIVE_FINANCIAL_QUEUE_ENABLED']=='true':
        raise ValueError('Native financial work remains held until shared retention mapping is reviewed')
    admin_email_otp_ttl(settings)
    native=settings['BURIMUNSI_NATIVE_ENABLED']=='true'
    workers=settings['BURIMUNSI_NATIVE_WORKERS_ENABLED']=='true'
    uploads=settings['BURIMUNSI_NATIVE_UPLOADS_ENABLED']=='true'
    group=settings['BURIMUNSI_COLLECTION_ID']
    if group and not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]{0,127}',group):raise ValueError('Canonical existing native collection identifier required')
    # An optional rollout filter is server-side only. The authenticated device
    # grant selects the real collection; an APK or deployment need not name it.
    if workers and not native:raise ValueError('Native workers require explicit native runtime enablement')
    if uploads and not native:raise ValueError('Native uploads require explicit native runtime enablement')
    observations=settings['BURIMUNSI_SMS_OBSERVATIONS_ENABLED']=='true'
    admin_observations=settings['BURIMUNSI_ADMIN_SMS_OBSERVATIONS_ENABLED']=='true'
    hints=settings['BURIMUNSI_OBSERVATION_HINTS_ENABLED']=='true'
    auto_transactions=settings['BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED']=='true'
    auto_records=settings['BURIMUNSI_NATIVE_AUTO_RECORDS_ENABLED']=='true'
    staff_phone=settings['BURIMUNSI_STAFF_PIN_PHONE_PRESERVATION_ENABLED']=='true'
    if (observations or staff_phone) and not native:
        raise ValueError('Native observation and staff-phone features require explicit native runtime enablement')
    if hints and not (observations or admin_observations):
        raise ValueError('Observation hints require an enabled observation surface')
    if auto_transactions and not (native and observations and settings['MOMO_AI_ENABLED']=='true'
                                   and settings['MOMO_AI_MODEL'] and settings['OPENAI_API_KEY']):
        raise ValueError('Automatic transactions require native capture and a configured parser')
    if auto_records and not auto_transactions:
        raise ValueError('Automatic transaction records require automatic processing')
    if settings['BURIMUNSI_CANONICAL_SCHEDULER_ENABLED']=='true':
        group_id=settings['BURIMUNSI_CANONICAL_SCHEDULER_COLLECTION_ID']
        owner=settings['BURIMUNSI_CANONICAL_SCHEDULER_OWNER']
        token=settings['BURIMUNSI_CANONICAL_SCHEDULER_MANAGED_ACCESS_TOKEN']
        identity=re.compile(r'[A-Za-z0-9][A-Za-z0-9_-]{0,127}')
        contract={'contract':'burimunsi.canonical-scheduler.v1','sourceSha256':source_sha,
                  'collectionId':group_id,'owner':owner,'receiptLimit':1,'rematchLimit':0}
        approval=hashlib.sha256(json.dumps(contract,sort_keys=True,separators=(',',':')).encode('utf8')).hexdigest()
        if (not native or not workers or not auto_transactions or settings['MOMO_PROCESSING_PAUSED']!='false'
            or settings['COLLECT_JOBS_MODE']!='receipt_processing_v1'
            or not identity.fullmatch(group_id) or not identity.fullmatch(owner)
            or group and group!=group_id or not 20<=len(token)<=8192
            or not re.fullmatch(r'[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+',token)
            or settings['BURIMUNSI_CANONICAL_SCHEDULER_APPROVAL_SHA256']!=approval):
            raise ValueError('Bound canonical scheduler configuration required')
    ingress_proof=validate_ingress_proof(settings,profile)
    digest=lambda key:bool(re.fullmatch(r'[a-f0-9]{64}',settings[key]))
    if settings['PRIVACY_RETENTION_V2_APPROVAL_SHA256'] and not digest('PRIVACY_RETENTION_V2_APPROVAL_SHA256'):raise ValueError('Exact v2 privacy policy approval digest required')
    smtp_ready=all(settings[k] for k in ('SMTP_HOST','SMTP_USER','SMTP_PASS','SMTP_ADMIN_EMAIL'))
    if settings['SMTP_HOST'] and (not re.fullmatch(r'[A-Za-z0-9.-]+',settings['SMTP_HOST']) or settings['SMTP_PORT'] not in ('465','587')):raise ValueError('Explicit SMTP TLS endpoint required')
    if settings['SMTP_ADMIN_EMAIL'] and not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+',settings['SMTP_ADMIN_EMAIL']):raise ValueError('Valid sender email required')
    if bool(settings['TURNSTILE_SITE_KEY'])!=bool(settings['TURNSTILE_SECRET_KEY']):raise ValueError('Turnstile requires both public site key and private secret')
    # Match the stricter native and Admin build contracts as well as the
    # challenge endpoint, before publishing an unusable configuration.
    if settings['TURNSTILE_SITE_KEY'] and not re.fullmatch(r'[A-Za-z0-9_-]{10,200}',settings['TURNSTILE_SITE_KEY']):raise ValueError('Valid Turnstile site key required')
    if profile['environment']=='production' and (settings['TURNSTILE_SITE_KEY'] in TURNSTILE_TEST_SITE_KEYS or settings['TURNSTILE_SECRET_KEY'] in TURNSTILE_TEST_SECRET_KEYS):raise ValueError('Documented Turnstile test keys cannot protect a production deployment')
    if settings['AUTH_ANONYMOUS_ENABLED']=='true' and (not settings['TURNSTILE_SITE_KEY'] or not settings['TURNSTILE_SECRET_KEY']):raise ValueError('Anonymous sign-in requires configured abuse protection')
    google=settings['GOOGLE_AUTH_ENABLED']=='true'
    if google!=(settings['GOTRUE_EXTERNAL_GOOGLE_ENABLED']=='true'):raise ValueError('Google runtime and Auth switches must agree')
    if google and (not settings['GOOGLE_CLIENT_ID'] or not settings['GOOGLE_SECRET'] or profile['google_callback_origin']!=profile['admin_origin']):raise ValueError('Both Google surfaces require credentials and the exact Admin callback origin')
    mode=settings['AUTH_PHONE_DELIVERY_MODE']
    if mode not in ('opensms_hook','twilio','twilio_verify'):raise ValueError('Reviewed Auth phone delivery mode required')
    phone=settings['AUTH_SMS_ENABLED']=='true' or settings['AUTH_WHATSAPP_ENABLED']=='true'
    if mode=='opensms_hook' and settings['AUTH_WHATSAPP_ENABLED']=='true':raise ValueError('Pinned Send SMS hook cannot distinguish WhatsApp; select a native provider mode')
    if mode!='opensms_hook' and phone:
        prefix='GOTRUE_SMS_'+mode.upper()+'_'
        if not re.fullmatch(r'AC[0-9a-fA-F]{32}',settings[prefix+'ACCOUNT_SID']) or len(settings[prefix+'AUTH_TOKEN'])<32 or not re.fullmatch(r'(?:MG|VA)[0-9a-fA-F]{32}',settings[prefix+'MESSAGE_SERVICE_SID']):raise ValueError('Native phone provider credentials and service required')
    if mode=='opensms_hook' and settings['AUTH_SMS_ENABLED']=='true':
        expected=profile['supabase_origin']+'/functions/v1/collect-sms'
        # Match the signed Send SMS hook's runtime namespace and credential
        # contract before declaring the enabled configuration usable.
        label=settings['OPENSMS_SENDER_LABEL'] or 'Your app'
        if (settings['OPENSMS_BASE_URL']!=expected
            or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]{0,79}',settings['OPENSMS_APPLICATION_ID'])
            or not re.fullmatch(r'app_[A-Za-z0-9_-]{32,252}',settings['OPENSMS_APPLICATION_TOKEN'])
            or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9 ._'-]{0,39}",label)
            or not re.fullmatch(r'[0-9]{2,3}',settings['OPENSMS_DISPATCH_TTL_SECONDS'])):
            raise ValueError('Same-deployment OTP-only OpenSMS application required')
        if settings['OPENSMS_APPLICATION_TOKEN']==settings['OPENSMS_RECEIPT_APPLICATION_TOKEN'] or settings['OPENSMS_APPLICATION_ID']==settings['OPENSMS_RECEIPT_APPLICATION_ID']:raise ValueError('OTP and receipt applications and credentials must be distinct')
        if settings['COLLECT_SMS_ENABLED']!='true':raise ValueError('OTP hook requires the approved local gateway')
    if not settings['OPENSMS_DISPATCH_TTL_SECONDS'].isdigit() or not 30<=int(settings['OPENSMS_DISPATCH_TTL_SECONDS'])<=300:raise ValueError('SMS dispatch TTL outside bounds')
    if settings['COLLECT_SMS_ENABLED']=='true' and not digest('COLLECT_SMS_APPROVAL_SHA256'):raise ValueError('Gateway source approval digest required')
    if not settings['OTP_SEGMENT_INTERVAL_MS'].isdigit() or not 1000<=int(settings['OTP_SEGMENT_INTERVAL_MS'])<=60000:raise ValueError('Gateway segment interval outside reviewed bounds')
    if not settings['MESSAGE_RETENTION_DAYS'].isdigit() or not 0<=int(settings['MESSAGE_RETENTION_DAYS'])<=3650:raise ValueError('Gateway message retention outside reviewed bounds')
    hosts=settings['CALLBACK_ALLOWED_HOSTS'].split(',') if settings['CALLBACK_ALLOWED_HOSTS'] else []
    if len(hosts)>32 or len(set(hosts))!=len(hosts) or any(not re.fullmatch(r'(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}',host) for host in hosts):raise ValueError('Explicit unique HTTPS callback host names required')
    if profile['environment']=='production' and settings['COLLECT_SMS_ENABLED']=='true' and (settings['OTP_REQUIRE_READY_GATEWAY']!='true' or settings['REQUIRE_ACTUAL_PARTS']!='true'):raise ValueError('Production gateway requires current readiness and actual part evidence')
    if settings['FCM_ENABLED']=='true' and (settings['COLLECT_SMS_ENABLED']!='true' or not fcm_identity(settings['OPENSMS_FCM_PROJECT_ID'],settings['OPENSMS_FCM_CLIENT_EMAIL'],settings['OPENSMS_FCM_PRIVATE_KEY'])):raise ValueError('Gateway wake FCM requires its separate configured service identity')
    if settings['COLLECT_RECEIPT_SMS_ENABLED']=='true':
        if settings['COLLECT_SMS_ENABLED']!='true' or settings['OPENSMS_RECEIPT_APPLICATION_TOKEN']==settings['OPENSMS_APPLICATION_TOKEN'] or settings['OPENSMS_RECEIPT_APPLICATION_ID']==settings['OPENSMS_APPLICATION_ID']:raise ValueError('Receipt delivery requires the approved local gateway and a distinct application')
        if settings['OPENSMS_RECEIPT_BASE_URL']!=profile['supabase_origin']+'/functions/v1/collect-sms' or not digest('COLLECT_RECEIPT_SMS_APPROVAL_SHA256') or not settings['OPENSMS_RECEIPT_APPLICATION_ID'] or len(settings['OPENSMS_RECEIPT_APPLICATION_TOKEN'])<32:raise ValueError('Receipt application and approval required')
    if settings['COLLECT_CONTRIBUTION_EMAIL_ENABLED']=='true' and (not settings['COLLECT_NOTICE_SMTP_PASSWORD'] or not digest('COLLECT_JOBS_EMAIL_APPROVAL_SHA256') or not settings['COLLECT_EMAIL_ADMITTED_FROM'].isdigit()):raise ValueError('Verified receipt email provider, start and approval required')
    if settings['COLLECT_PUSH_ENABLED']=='true' and (not settings['FCM_PROJECT_ID'] or not settings['FCM_SERVICE_ACCOUNT_JSON'] or not digest('COLLECT_JOBS_PUSH_APPROVAL_SHA256') or not settings['COLLECT_PUSH_ADMITTED_FROM'].isdigit()):raise ValueError('Verified push provider, start and approval required')
    if settings['FCM_ANDROID_PACKAGE'] not in ('app.cool.mobile','app.cool.mobile.dev') or profile['environment']=='production' and settings['FCM_ANDROID_PACKAGE']!='app.cool.mobile':raise ValueError('Exact registered member Android package required')
    if settings['FCM_SERVICE_ACCOUNT_JSON']:
        account=parse_fcm_account_json(settings['FCM_SERVICE_ACCOUNT_JSON'])
        if account.get('type')!='service_account' or account.get('project_id')!=settings['FCM_PROJECT_ID'] or account.get('token_uri')!='https://oauth2.googleapis.com/token' or account.get('universe_domain','googleapis.com')!='googleapis.com' or not isinstance(account.get('private_key_id'),str) or not re.fullmatch(r'[-A-Za-z0-9_]{1,128}',account.get('private_key_id','')) or not fcm_identity(settings['FCM_PROJECT_ID'],account.get('client_email',''),account.get('private_key','')):raise ValueError('Exact member push service identity required')
    if settings['MOMO_PROCESSING_PAUSED']=='false' and (settings['MOMO_AI_ENABLED']!='true' or not settings['OPENAI_API_KEY'] or not settings['MOMO_AI_MODEL'] or not digest('COLLECT_JOBS_PROCESSING_APPROVAL_SHA256')):raise ValueError('Reviewed receipt extraction provider required')
    native_jpeg_ocr_configuration(settings,source_sha)
    return {'smtp_configured':smtp_ready,'google_configured':google,'source_sha256':source_sha,'configuration_only':True,
            'burimunsi_native_requested':native,'burimunsi_workers_requested':workers,
            'burimunsi_uploads_requested':uploads,'burimunsi_commissioned':False,
            'burimunsi_collection_verified':False,'burimunsi_attested_network_resolver_required':native,
            'burimunsi_ingress_review_record_configured':ingress_proof,'burimunsi_live_edge_verified':False}

def configure(release:Path):
    release=release.resolve(strict=True);meta=json.loads((release/'release.json').read_text());profile=meta['profile']
    settings_file=release/'private/provider-settings.json';private_file(settings_file)
    settings=read_provider_settings(settings_file);status=validated_settings(settings,profile,meta['source_sha256'])
    stack=read_env(release/'private/stack.env');functions=read_env(release/'private/functions.env');public=read_env(release/'public.env')
    native_keys=native_private_configuration(release,settings,functions,stack)
    ingress_keys=ingress_private_configuration(release,settings,functions,stack)
    stack.update(settings)
    stack.update(native_keys);functions.update(native_keys);stack.update(ingress_keys);functions.update(ingress_keys)
    function_settings={k:v for k,v in settings.items() if not k.startswith(('SMTP_','GOTRUE_','COLLECT_AUTH_')) and k not in AUTH_PRIVATE_PROVIDER_FIELDS}
    functions.update(function_settings)
    for k in list(functions):
        if k.startswith(('SMTP_','GOTRUE_','COLLECT_AUTH_')) or k in AUTH_PRIVATE_PROVIDER_FIELDS:del functions[k]
    for key in list(public):
        if key.startswith(('BURIMUNSI_','COLLECT_NATIVE_INGRESS_')) or key in PRIVATE_FEATURE_CONTROLS:del public[key]
    for suffix in ('ANONYMOUS','SMS','WHATSAPP'):
        public['COLLECT_'+suffix+'_AUTH_ENABLED']=settings['AUTH_'+suffix+'_ENABLED']
    public['COLLECT_GOOGLE_AUTH_ENABLED']=settings['GOOGLE_AUTH_ENABLED']
    public['AUTH_PHONE_DELIVERY_MODE']=settings['AUTH_PHONE_DELIVERY_MODE']
    public['AUTH_WHATSAPP_ENABLED']=settings['AUTH_WHATSAPP_ENABLED']
    public['AUTH_CAPTCHA_ENABLED']='true' if profile['environment']=='production' or settings['TURNSTILE_SITE_KEY'] else 'false'
    public['AUTH_CAPTCHA_PROVIDER']='turnstile'
    public['AUTH_CAPTCHA_SITE_KEY']=settings['TURNSTILE_SITE_KEY']
    public['COLLECT_ASSISTED_SMS_ENABLED']='true' if settings['COLLECT_SMS_ENABLED']=='true' and settings['COLLECT_RECEIPT_SMS_ENABLED']=='true' else 'false'
    stack['ENABLE_ANONYMOUS_USERS']=settings['AUTH_ANONYMOUS_ENABLED']
    stack['ENABLE_PHONE_SIGNUP']='true' if settings['AUTH_SMS_ENABLED']=='true' or settings['AUTH_WHATSAPP_ENABLED']=='true' else 'false'
    stack['GOTRUE_HOOK_SEND_SMS_ENABLED']='true' if settings['AUTH_PHONE_DELIVERY_MODE']=='opensms_hook' and settings['AUTH_SMS_ENABLED']=='true' else 'false'
    stack['GOTRUE_SMS_PROVIDER']='twilio' if settings['AUTH_PHONE_DELIVERY_MODE']=='opensms_hook' else settings['AUTH_PHONE_DELIVERY_MODE']
    stack['GOTRUE_SECURITY_CAPTCHA_ENABLED']='true' if profile['environment']=='production' or settings['TURNSTILE_SITE_KEY'] else 'false'
    projections=[(release/'private/stack.env',dotenv(stack),0o600),
                 (release/'private/functions.env',dotenv(functions),0o600),
                 (release/'public.env',dotenv(public),0o644)]
    for path,content,mode in projections:
        temp=path.with_suffix(path.suffix+'.next')
        with temp.open('x',encoding='utf8') as out:os.chmod(temp,mode);out.write(content)
        temp.replace(path)
    temp=release/'client.json.next'
    with temp.open('x') as out:os.chmod(temp,0o644);json.dump(public,out,sort_keys=True,indent=2);out.write('\n')
    temp.replace(release/'client.json')
    seal_configuration(release)
    return status

def export_native_ingress_environment(release:Path,output:Path,socket:Path):
    """Explicit new private projection from a sealed release; no configuration
    change, key generation, existing-file overwrite or service operation."""
    release=release.resolve(strict=True);verify_configuration(release)
    receipt_raw=(release/'private/configuration.json').read_bytes();receipt=json.loads(receipt_raw)
    captured={}
    for name in ('release.json','private/provider-settings.json','private/functions.env','private/stack.env','private/keys.json'):
        path=release/name
        if name.startswith('private/'):private_file(path)
        captured[name]=path.read_bytes()
        if hashlib.sha256(captured[name]).hexdigest()!=receipt['files'][name]:raise ValueError('Sealed native ingress input changed')
    meta=json.loads(captured['release.json']);profile=meta['profile']
    try:
        settings=native_defaults(json.loads(captured['private/provider-settings.json'],object_pairs_hook=native_unique_pairs))
        keys=json.loads(captured['private/keys.json'],object_pairs_hook=native_unique_pairs)
        functions=parse_env(captured['private/functions.env'].decode('utf8'));stack=parse_env(captured['private/stack.env'].decode('utf8'))
    except (ValueError,TypeError,RecursionError):raise ValueError('Sealed native ingress input is invalid') from None
    validated_settings(settings,profile,meta['source_sha256'])
    if not isinstance(keys,dict):raise ValueError('Sealed native ingress keys are invalid')
    ingress=ingress_private_configuration(release,settings,functions,stack,keys=keys)
    if not output.is_absolute() or output.parent.resolve(strict=True)!=output.parent:
        raise ValueError('New absolute physical private ingress output required')
    parent=output.parent.lstat()
    if not output.parent.is_dir() or parent.st_uid!=os.getuid() or parent.st_mode&0o077:
        raise ValueError('Owned mode0700 ingress output parent required')
    path=str(socket)
    if not socket.is_absolute() or len(path)>100 or path!=str(Path(os.path.normpath(path))) or re.search(r'[\x00-\x20\x7f]',path):
        raise ValueError('Explicit absolute protected ingress socket required')
    expected={'COLLECT_DEPLOYMENT_PROFILE':canonical_profile(profile),'COLLECT_DEPLOYMENT_PROFILE_SHA256':profile_sha256(profile),
              'APP_ENVIRONMENT':profile['environment'],'SUPABASE_URL':profile['supabase_origin']}
    if any(functions.get(name)!=value for name,value in expected.items()):raise ValueError('Sealed native ingress profile mismatch')
    values={**expected,**{name:ingress.get(name,'') for name in INGRESS_PRIVATE_KEYS},
            **{name:settings[name] for name in INGRESS_CONTROLS},
            'SUPABASE_INTERNAL_URL':'http://127.0.0.1:55101','COLLECT_NATIVE_INGRESS_SOCKET':path,
            **{name:settings[name] for name in ('BURIMUNSI_NATIVE_ENABLED','AUTH_PHONE_DELIVERY_MODE','AUTH_WHATSAPP_ENABLED')}}
    raw=dotenv(values).encode('utf8');configuration=hashlib.sha256(receipt_raw).hexdigest()
    verify_configuration(release)
    if (release/'private/configuration.json').read_bytes()!=receipt_raw:raise ValueError('Sealed native ingress configuration changed')
    descriptor=os.open(output,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
    with os.fdopen(descriptor,'wb') as destination:destination.write(raw);destination.flush();os.fsync(destination.fileno())
    return {'format':'collect.native-ingress.projection.v1','profile_sha256':meta['profile_sha256'],'source_sha256':meta['source_sha256'],
            'configuration_sha256':configuration,'environment_sha256':hashlib.sha256(raw).hexdigest(),'fields':sorted(values),
            'native_requested':settings['BURIMUNSI_NATIVE_ENABLED']=='true','commissioned':False}

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--release',type=Path,required=True)
    p.add_argument('--export-native-ingress-env',type=Path);p.add_argument('--ingress-socket',type=Path);a=p.parse_args()
    if bool(a.export_native_ingress_env)!=bool(a.ingress_socket):p.error('Ingress export and explicit socket must be supplied together')
    try:print(json.dumps(export_native_ingress_environment(a.release,a.export_native_ingress_env,a.ingress_socket) if a.export_native_ingress_env else configure(a.release),sort_keys=True))
    except (OSError,ValueError,KeyError) as error:print('Provider configuration refused: '+type(error).__name__+'. Private values were not printed.',file=sys.stderr);sys.exit(1)
