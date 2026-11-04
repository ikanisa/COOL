"""Validate private provider settings and project them into exact service scopes.

This changes files only. It never enables a Cron job, makes a provider request,
starts a container, or replaces signing/data/session keys.
"""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import re
import sys
sys.dont_write_bytecode=True
from urllib.parse import urlsplit
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from scripts.self_hosted.prepare import PROVIDER_SETTINGS,dotenv,seal_configuration,CONFIGURATION_FILES

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

def verify_configuration(release):
    path=release/'private/configuration.json';private_file(path)
    receipt=json.loads(path.read_text());meta=json.loads((release/'release.json').read_text())
    if set(receipt)!={'format','profile_sha256','source_sha256','files'} or receipt['format']!='collect.selfhost.configuration.v1' or receipt['profile_sha256']!=meta['profile_sha256'] or receipt['source_sha256']!=meta['source_sha256'] or set(receipt['files'])!=set(CONFIGURATION_FILES):raise ValueError('Exact configured release receipt required')
    import hashlib
    if any(hashlib.sha256((release/name).read_bytes()).hexdigest()!=digest for name,digest in receipt['files'].items()):raise ValueError('Configuration changed or projection was interrupted; configure before operating')

def read_env(path):
    values={}
    for line in path.read_text().splitlines():
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

def validated_settings(settings,profile,source_sha):
    if not isinstance(settings,dict) or set(settings)!=set(PROVIDER_SETTINGS) or any(not isinstance(v,str) or '\0' in v or len(v)>32768 for v in settings.values()):raise ValueError('Exact provider settings contract required')
    flags=[k for k,v in PROVIDER_SETTINGS.items() if v in ('true','false')]
    if any(settings[k] not in ('true','false') for k in flags):raise ValueError('Provider switches require true or false')
    digest=lambda key:bool(re.fullmatch(r'[a-f0-9]{64}',settings[key]))
    if settings['PRIVACY_RETENTION_V2_APPROVAL_SHA256'] and not digest('PRIVACY_RETENTION_V2_APPROVAL_SHA256'):raise ValueError('Exact v2 privacy policy approval digest required')
    smtp_ready=all(settings[k] for k in ('SMTP_HOST','SMTP_USER','SMTP_PASS','SMTP_ADMIN_EMAIL'))
    if settings['SMTP_HOST'] and (not re.fullmatch(r'[A-Za-z0-9.-]+',settings['SMTP_HOST']) or settings['SMTP_PORT'] not in ('465','587')):raise ValueError('Explicit SMTP TLS endpoint required')
    if settings['SMTP_ADMIN_EMAIL'] and not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+',settings['SMTP_ADMIN_EMAIL']):raise ValueError('Valid sender email required')
    if bool(settings['TURNSTILE_SITE_KEY'])!=bool(settings['TURNSTILE_SECRET_KEY']):raise ValueError('Turnstile requires both public site key and private secret')
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
        if settings['OPENSMS_APPLICATION_TOKEN']==settings['OPENSMS_RECEIPT_APPLICATION_TOKEN']:raise ValueError('OTP and receipt credentials must be distinct')
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
        account=json.loads(settings['FCM_SERVICE_ACCOUNT_JSON'])
        if not isinstance(account,dict) or len(settings['FCM_SERVICE_ACCOUNT_JSON'].encode())>16384 or account.get('type')!='service_account' or account.get('project_id')!=settings['FCM_PROJECT_ID'] or account.get('token_uri')!='https://oauth2.googleapis.com/token' or account.get('universe_domain','googleapis.com')!='googleapis.com' or not isinstance(account.get('private_key_id'),str) or not re.fullmatch(r'[-A-Za-z0-9_]{1,128}',account.get('private_key_id','')) or not fcm_identity(settings['FCM_PROJECT_ID'],account.get('client_email',''),account.get('private_key','')):raise ValueError('Exact member push service identity required')
    if settings['MOMO_PROCESSING_PAUSED']=='false' and (settings['MOMO_AI_ENABLED']!='true' or not settings['OPENAI_API_KEY'] or not settings['MOMO_AI_MODEL'] or not digest('COLLECT_JOBS_PROCESSING_APPROVAL_SHA256')):raise ValueError('Reviewed receipt extraction provider required')
    if settings['ROSTER_AI_APPROVAL_JSON'] or settings['ROSTER_AI_APPROVAL_SHA256']:raise ValueError('Roster PDF/image AI requires a qualified Supabase-native decoder; the current Python/SQLite helper is not admitted by this deployment')
    return {'smtp_configured':smtp_ready,'google_configured':google,'source_sha256':source_sha,'configuration_only':True}

def configure(release:Path):
    release=release.resolve(strict=True);meta=json.loads((release/'release.json').read_text());profile=meta['profile']
    settings_file=release/'private/provider-settings.json';private_file(settings_file)
    settings=json.loads(settings_file.read_text());status=validated_settings(settings,profile,meta['source_sha256'])
    stack=read_env(release/'private/stack.env');functions=read_env(release/'private/functions.env');public=read_env(release/'public.env')
    stack.update(settings)
    function_settings={k:v for k,v in settings.items() if not k.startswith(('SMTP_','GOTRUE_')) and k not in ('GOOGLE_SECRET','GOOGLE_CLIENT_ID')}
    functions.update(function_settings)
    for k in list(functions):
        if k.startswith(('SMTP_','GOTRUE_')) or k in ('GOOGLE_SECRET','GOOGLE_CLIENT_ID'):del functions[k]
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
    for path,values,mode in [(release/'private/stack.env',stack,0o600),(release/'private/functions.env',functions,0o600),(release/'public.env',public,0o644)]:
        temp=path.with_suffix(path.suffix+'.next')
        with temp.open('x') as out:os.chmod(temp,mode);out.write(dotenv(values))
        temp.replace(path)
    temp=release/'client.json.next'
    with temp.open('x') as out:os.chmod(temp,0o644);json.dump(public,out,sort_keys=True,indent=2);out.write('\n')
    temp.replace(release/'client.json')
    seal_configuration(release)
    return status

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--release',type=Path,required=True);a=p.parse_args()
    try:print(json.dumps(configure(a.release),sort_keys=True))
    except (OSError,ValueError,KeyError) as error:print('Provider configuration refused: '+type(error).__name__+'. Private values were not printed.',file=sys.stderr);sys.exit(1)
