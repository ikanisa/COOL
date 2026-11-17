"""Synthetic protected-file projection only. No real release/provider/runtime."""
import base64
import json
import hashlib
import time
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from scripts.self_hosted.prepare import CONFIGURATION_FILES,PRIVATE_KEYS,PRIVATE_FEATURE_CONTROLS,PROVIDER_SETTINGS,build_compose,dotenv,verify_vendor,seal_configuration
from scripts.self_hosted.configure import configure,read_env,validated_settings,native_defaults,NATIVE_CONTROLS,NATIVE_PRIVATE_KEYS,INGRESS_CONTROLS,INGRESS_PRIVATE_KEYS,export_native_ingress_environment
from scripts.supabase.deployment_profile import profile_sha256,canonical_profile

PROFILE={'format':'collect.deployment.v1','id':'native-projection-fixture','mode':'self_hosted','environment':'qualification',
 'supabase_origin':'https://supabase.example.test','member_api_origin':'https://member.example.test',
 'admin_origin':'https://admin.example.test','public_origin':'https://public.example.test','google_callback_origin':'https://admin.example.test'}
def key(byte):return base64.b64encode(bytes([byte])*32).decode()
def private_keys():return {'format':'collect.selfhost.private-keys.v1','DATA_KEY_ID':'retained-data-v1','DATA_ENCRYPTION_KEY':key(1),
 'SESSION_KEY_ID':'retained-bff-v1','SESSION_ENCRYPTION_KEY':key(2),'JWT_SECRET':'retained-signing-$literal',
 'SERVICE_ROLE_KEY':'retained-service-key','BURIMUNSI_PIN_PEPPER_ID':'native-pin-v1',
 'BURIMUNSI_PIN_PEPPER_BASE64':key(3),'BURIMUNSI_CURSOR_KEY_BASE64':key(4),
 'COLLECT_NATIVE_INGRESS_KEY_ID':'synthetic-ingress-v1','COLLECT_NATIVE_INGRESS_KEY_BASE64':key(5)}
def ingress_proof(changes=None):
 now=int(time.time()*1000)
 legacy=changes and changes.get('format')=='collect.native-ingress.edge-proof.v1'
 guard={'nativeWorkerGuardRuleId':'b'*32,'nativeWorkerGuardExpression':'(http.host eq "supabase.example.test" and starts_with(http.request.uri.path, "/functions/v1/collect-api/v1/burimunsi") and cf.worker.upstream_zone ne "")',
        'expiresAt':now+3600000} if legacy else {'nativeWorkerGuard':'origin_cf_worker_presence_reject'}
 proof={'format':'collect.native-ingress.edge-proof.v2','status':'reviewed','profileSha256':profile_sha256(PROFILE),'supabaseOrigin':PROFILE['supabase_origin'],
  'tunnelId':'f1000000-0000-4000-8000-000000000001',
  'directTunnelOnly':True,'protectedUnixSocket':True,'pseudoIpv4':'off','reviewedAt':now-10000,'evidenceSha256':'c'*64,**guard,**(changes or {})}
 raw=json.dumps(proof,sort_keys=True,separators=(',',':'))
 return {'COLLECT_NATIVE_INGRESS_EDGE_PROOF_JSON':raw,'COLLECT_NATIVE_INGRESS_EDGE_PROOF_SHA256':hashlib.sha256(raw.encode()).hexdigest()}

class NativeEnvironmentProjection(unittest.TestCase):
 def fixture(self,*,keys=None,settings=None):
  area=tempfile.TemporaryDirectory();self.addCleanup(area.cleanup);root=Path(area.name).resolve();(root/'private').mkdir(mode=0o700)
  for name in CONFIGURATION_FILES:
   path=root/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text('synthetic fixture')
   path.chmod(0o600 if name.startswith('private/') else 0o644)
  (root/'release.json').write_text(json.dumps({'profile':PROFILE,'profile_sha256':profile_sha256(PROFILE),'source_sha256':'a'*64}))
  chosen=private_keys() if keys is None else keys
  (root/'private/keys.json').write_text(json.dumps(chosen))
  (root/'private/provider-settings.json').write_text(json.dumps(dict(PROVIDER_SETTINGS) if settings is None else settings))
  retained={name:value for name,value in chosen.items() if name not in NATIVE_PRIVATE_KEYS and name!='format'}
  (root/'private/stack.env').write_text(dotenv({**retained,'PRESERVED_STACK':'original'}))
  (root/'private/functions.env').write_text(dotenv({**retained,'PRESERVED_FUNCTIONS':'original'}))
  (root/'public.env').write_text(dotenv({'SUPABASE_PUBLISHABLE_KEY':'sb_publishable_synthetic','PUBLIC':'original'}))
  (root/'private/configuration.json').write_text('retained synthetic receipt');(root/'private/configuration.json').chmod(0o600)
  return root,chosen
 def outputs(self,root):return {name:(root/name).read_bytes() for name in ('private/keys.json','private/provider-settings.json',
  'private/stack.env','private/functions.env','public.env','client.json','private/configuration.json')}
 def assert_no_native_public(self,root):
  for name in ('public.env','client.json'):
   value=(root/name).read_text();self.assertNotIn('BURIMUNSI_',value);self.assertNotIn('COLLECT_NATIVE_INGRESS_',value)
   for field in PRIVATE_FEATURE_CONTROLS:self.assertNotIn(field,value)
   for secret in (key(1),key(2),key(3),key(4),key(5)):self.assertNotIn(secret,value)
 def test_fresh_private_projection_preserves_original_keys_and_defaults_off(self):
  root,keys=self.fixture();before=(root/'private/keys.json').read_bytes()
  with patch('scripts.self_hosted.prepare.subprocess.run') as command:status=configure(root)
  command.assert_not_called();self.assertEqual((root/'private/keys.json').read_bytes(),before)
  for name in ('stack.env','functions.env'):
   values=read_env(root/'private'/name)
   for field in (*NATIVE_PRIVATE_KEYS,*INGRESS_PRIVATE_KEYS):self.assertEqual(values[field],keys[field])
   for field in ('DATA_ENCRYPTION_KEY','SESSION_ENCRYPTION_KEY','JWT_SECRET','SERVICE_ROLE_KEY'):self.assertEqual(values[field],keys[field])
   self.assertEqual({field:values[field] for field in NATIVE_CONTROLS},NATIVE_CONTROLS)
   self.assertEqual({field:values[field] for field in PRIVATE_FEATURE_CONTROLS},PRIVATE_FEATURE_CONTROLS)
   self.assertEqual((root/'private'/name).stat().st_mode&0o777,0o600)
  self.assert_no_native_public(root);self.assertFalse(status['burimunsi_commissioned'])
 def test_legacy_provider_settings_gain_private_defaults_without_rewrite(self):
  previous={name:value for name,value in PROVIDER_SETTINGS.items() if name not in PRIVATE_FEATURE_CONTROLS}
  root,_=self.fixture(settings=previous);before=(root/'private/provider-settings.json').read_bytes()
  # A retained projection may contain stale values; absent provider switches
  # must explicitly replace those values with the backward-compatible default.
  for name in ('private/stack.env','private/functions.env'):
   path=root/name;values=read_env(path);values.update({field:'true' for field in PRIVATE_FEATURE_CONTROLS})
   path.write_text(dotenv(values))
  configure(root)
  self.assertEqual((root/'private/provider-settings.json').read_bytes(),before)
  for name in ('private/stack.env','private/functions.env'):
   values=read_env(root/name)
   self.assertEqual({field:values[field] for field in PRIVATE_FEATURE_CONTROLS},PRIVATE_FEATURE_CONTROLS)
  self.assert_no_native_public(root)
 def test_optional_switch_subsets_default_off_without_accepting_other_missing_fields(self):
  fields=list(PRIVATE_FEATURE_CONTROLS)
  for mask in range(1<<len(fields)):
   missing={field for index,field in enumerate(fields) if mask&(1<<index)}
   settings={name:value for name,value in PROVIDER_SETTINGS.items() if name not in missing}
   for field in set(fields)-missing:settings[field]='true'
   normalized=native_defaults(settings)
   self.assertEqual({field:normalized[field] for field in fields},
                    {field:('false' if field in missing else 'true') for field in fields})
  previous={name:value for name,value in PROVIDER_SETTINGS.items() if name not in PRIVATE_FEATURE_CONTROLS}
  for invalid in ({**previous,'UNREVIEWED_SWITCH':'true'},
                  {name:value for name,value in previous.items() if name!='SMTP_HOST'}):
   with self.assertRaisesRegex(ValueError,'Exact provider settings'):validated_settings(invalid,PROFILE,'a'*64)
 def test_private_feature_flags_project_without_public_leaks(self):
  settings={**PROVIDER_SETTINGS,**ingress_proof(),'BURIMUNSI_NATIVE_ENABLED':'true',
            'MOMO_AI_ENABLED':'true','MOMO_AI_MODEL':'synthetic-model','OPENAI_API_KEY':'synthetic-test-key',
            **{name:('false' if name=='BURIMUNSI_NATIVE_FINANCIAL_QUEUE_ENABLED' else 'true') for name in PRIVATE_FEATURE_CONTROLS}}
  root,keys=self.fixture(settings=settings);before=(root/'private/keys.json').read_bytes()
  public=read_env(root/'public.env');public.update({name:'true' for name in PRIVATE_FEATURE_CONTROLS})
  (root/'public.env').write_text(dotenv(public))
  configure(root)
  self.assertEqual((root/'private/keys.json').read_bytes(),before)
  for name in ('private/stack.env','private/functions.env'):
   values=read_env(root/name)
   self.assertEqual({field:values[field] for field in PRIVATE_FEATURE_CONTROLS},
                    {field:('false' if field=='BURIMUNSI_NATIVE_FINANCIAL_QUEUE_ENABLED' else 'true') for field in PRIVATE_FEATURE_CONTROLS})
   self.assertEqual((root/name).stat().st_mode&0o777,0o600)
  self.assert_no_native_public(root)
 def test_private_feature_flags_validate_before_projection(self):
  with self.assertRaisesRegex(ValueError,'retention mapping is reviewed'):
   validated_settings({**PROVIDER_SETTINGS,'BURIMUNSI_NATIVE_FINANCIAL_QUEUE_ENABLED':'true'},PROFILE,'a'*64)
  for name in PRIVATE_FEATURE_CONTROLS:
   for value in ('TRUE','1','',True):
    with self.subTest(name=name,value=value),self.assertRaises(ValueError):
     validated_settings({**PROVIDER_SETTINGS,name:value},PROFILE,'a'*64)
   root,_=self.fixture(settings={**PROVIDER_SETTINGS,name:'TRUE'});before=self.outputs(root)
   with self.assertRaises(ValueError):configure(root)
   self.assertEqual(self.outputs(root),before)
  for name in ('BURIMUNSI_SMS_OBSERVATIONS_ENABLED','BURIMUNSI_STAFF_PIN_PHONE_PRESERVATION_ENABLED'):
   root,_=self.fixture(settings={**PROVIDER_SETTINGS,name:'true'});before=self.outputs(root)
   with self.assertRaisesRegex(ValueError,'native runtime enablement'):configure(root)
   self.assertEqual(self.outputs(root),before)
  with self.assertRaisesRegex(ValueError,'enabled observation surface'):
   validated_settings({**PROVIDER_SETTINGS,'BURIMUNSI_OBSERVATION_HINTS_ENABLED':'true'},PROFILE,'a'*64)
  with self.assertRaisesRegex(ValueError,'configured parser'):
   validated_settings({**PROVIDER_SETTINGS,'BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED':'true',
                       'BURIMUNSI_NATIVE_ENABLED':'true','BURIMUNSI_SMS_OBSERVATIONS_ENABLED':'true'},PROFILE,'a'*64)
  # Managed Admin review may remain available independently of native intake.
  validated_settings({**PROVIDER_SETTINGS,'BURIMUNSI_ADMIN_SMS_OBSERVATIONS_ENABLED':'true',
                      'BURIMUNSI_OBSERVATION_HINTS_ENABLED':'true'},PROFILE,'a'*64)
  # Inspection is independent of the observation and native runtime flags.
  validated_settings({**PROVIDER_SETTINGS,'BURIMUNSI_RETENTION_INSPECTION_ENABLED':'true'},PROFILE,'a'*64)
  # The two protected-owner server switches are intentionally independent.
  for identity in ('true','false'):
   for authority in ('true','false'):
    validated_settings({**PROVIDER_SETTINGS,'COLLECT_ADMIN_OWNER_IDENTITY_ENABLED':identity,
                        'COLLECT_ADMIN_DYNAMIC_OWNER_AUTH_ENABLED':authority},PROFILE,'a'*64)
 def test_auth_captcha_secret_is_removed_from_existing_edge_projection(self):
  secret='synthetic-private-captcha-secret'
  settings={**PROVIDER_SETTINGS,'TURNSTILE_SITE_KEY':'synthetic-public-captcha-site','TURNSTILE_SECRET_KEY':secret}
  root,_=self.fixture(settings=settings)
  path=root/'private/functions.env';values=read_env(path)
  values.update({'TURNSTILE_SECRET_KEY':secret,'COLLECT_AUTH_TURNSTILE_SECRET':secret,'COLLECT_AUTH_SMTP_PASS':'synthetic-private-smtp'})
  path.write_text(dotenv(values))
  configure(root)
  functions=read_env(path);stack=read_env(root/'private/stack.env')
  self.assertEqual(stack['TURNSTILE_SECRET_KEY'],secret)
  self.assertEqual(functions['TURNSTILE_SITE_KEY'],settings['TURNSTILE_SITE_KEY'])
  for name in ('TURNSTILE_SECRET_KEY','COLLECT_AUTH_TURNSTILE_SECRET','COLLECT_AUTH_SMTP_PASS'):
   self.assertNotIn(name,functions)
  for name in ('public.env','client.json'):
   self.assertNotIn(secret,(root/name).read_text())
 def test_existing_text_and_uuid_collection_identifiers_are_configuration_only(self):
  for group in ('legacy-buri-group','f1000000-0000-4000-8000-000000000001'):
   with self.subTest(group=group):
    settings={**PROVIDER_SETTINGS,**ingress_proof(),'BURIMUNSI_NATIVE_ENABLED':'true','BURIMUNSI_NATIVE_WORKERS_ENABLED':'true','BURIMUNSI_COLLECTION_ID':group}
    root,keys=self.fixture(settings=settings);status=configure(root)
    values=read_env(root/'private/functions.env');self.assertEqual(values['BURIMUNSI_COLLECTION_ID'],group)
    self.assertTrue(status['burimunsi_attested_network_resolver_required']);self.assertFalse(status['burimunsi_collection_verified']);self.assertFalse(status['burimunsi_commissioned'])
    self.assert_no_native_public(root)
 def test_legacy_all_missing_stays_off_without_generating_or_changing_keys(self):
  keys={name:value for name,value in private_keys().items() if name not in (*NATIVE_PRIVATE_KEYS,*INGRESS_PRIVATE_KEYS)}
  settings={name:value for name,value in PROVIDER_SETTINGS.items() if name not in (*NATIVE_CONTROLS,*INGRESS_CONTROLS)}
  root,_=self.fixture(keys=keys,settings=settings);before=self.outputs(root)
  with patch('scripts.self_hosted.prepare.subprocess.run') as command:configure(root)
  command.assert_not_called()
  for name in ('private/keys.json','private/provider-settings.json'):self.assertEqual((root/name).read_bytes(),before[name])
  values=read_env(root/'private/functions.env');self.assertEqual(values['BURIMUNSI_NATIVE_ENABLED'],'false')
  self.assertTrue(all(name not in values for name in NATIVE_PRIVATE_KEYS))
 def test_legacy_missing_keys_refuses_enable_before_any_projection(self):
  keys={name:value for name,value in private_keys().items() if name not in NATIVE_PRIVATE_KEYS}
  root,_=self.fixture(keys=keys,settings={**PROVIDER_SETTINGS,**ingress_proof(),'BURIMUNSI_NATIVE_ENABLED':'true','BURIMUNSI_COLLECTION_ID':'existing-group'})
  before=self.outputs(root)
  with self.assertRaisesRegex(ValueError,'explicit retained-key'):configure(root)
  self.assertEqual(self.outputs(root),before);self.assertEqual(list(root.rglob('*.next')),[])
 def test_partial_or_changed_native_key_identity_never_rotates_any_key(self):
  for field in NATIVE_PRIVATE_KEYS:
   with self.subTest(field=field):
    keys=private_keys();del keys[field];root,_=self.fixture(keys=keys);before=self.outputs(root)
    with self.assertRaisesRegex(ValueError,'incomplete'):configure(root)
    self.assertEqual(self.outputs(root),before)
  root,keys=self.fixture();path=root/'private/functions.env';values=read_env(path);values['BURIMUNSI_PIN_PEPPER_BASE64']=key(7);path.write_text(dotenv(values));before=self.outputs(root)
  with self.assertRaisesRegex(ValueError,'no automatic rotation'):configure(root)
  self.assertEqual(self.outputs(root),before)
 def test_native_key_format_and_independent_purposes_fail_closed(self):
  cases=[('BURIMUNSI_PIN_PEPPER_BASE64','invalid native secret'),('BURIMUNSI_PIN_PEPPER_ID','invalid native secret'),
   ('BURIMUNSI_CURSOR_KEY_BASE64',key(4).rstrip('=')),('BURIMUNSI_CURSOR_KEY_BASE64',key(3)),
   ('BURIMUNSI_PIN_PEPPER_BASE64',key(1)),('BURIMUNSI_CURSOR_KEY_BASE64',key(2))]
  for field,value in cases:
   with self.subTest(field=field,value_kind=len(value)):
    keys=private_keys();keys[field]=value;root,_=self.fixture(keys=keys);before=self.outputs(root)
    with self.assertRaises(ValueError) as caught:configure(root)
    self.assertNotIn(value,str(caught.exception));self.assertIsNone(caught.exception.__context__)
    self.assertEqual(self.outputs(root),before);self.assertEqual(list(root.rglob('*.next')),[])
 def test_prior_data_or_bff_material_cannot_be_reused(self):
  for name in ('DATA_DECRYPTION_KEYS_JSON','SESSION_DECRYPTION_KEYS_JSON'):
   with self.subTest(name=name):
    root,_=self.fixture();path=root/'private/functions.env';values=read_env(path);values[name]=json.dumps({'old':key(3)});path.write_text(dotenv(values));before=self.outputs(root)
    with self.assertRaisesRegex(ValueError,'reuse DATA or BFF'):configure(root)
    self.assertEqual(self.outputs(root),before)
 def test_duplicate_protected_key_and_rotation_ring_fields_are_not_silently_overwritten(self):
  root,_=self.fixture();path=root/'private/keys.json';text=path.read_text();path.write_text(text[:-1]+',"BURIMUNSI_PIN_PEPPER_ID":"shadow"}');before=self.outputs(root)
  with self.assertRaises(ValueError):configure(root)
  self.assertEqual(self.outputs(root),before)
  root,_=self.fixture();path=root/'private/functions.env';values=read_env(path);values['DATA_DECRYPTION_KEYS_JSON']='{"old":"'+key(3)+'","old":"'+key(5)+'"}';path.write_text(dotenv(values));before=self.outputs(root)
  with self.assertRaises(ValueError):configure(root)
  self.assertEqual(self.outputs(root),before)
 def test_workers_uploads_and_collection_filter_are_server_side(self):
  cases=[{'BURIMUNSI_NATIVE_WORKERS_ENABLED':'true'},
   {'BURIMUNSI_NATIVE_UPLOADS_ENABLED':'true'},
   {'BURIMUNSI_NATIVE_ENABLED':'true'}, {'BURIMUNSI_COLLECTION_ID':'../group'},
   {'BURIMUNSI_NATIVE_ENABLED':'TRUE'}, {'BURIMUNSI_NATIVE_WORKERS_ENABLED':'1'},
   {'BURIMUNSI_NATIVE_UPLOADS_ENABLED':'TRUE'}]
  for change in cases:
   with self.subTest(change=change),self.assertRaises(ValueError):validated_settings({**PROVIDER_SETTINGS,**change},PROFILE,'a'*64)
 def test_authoritative_runtime_scope_needs_no_deployment_collection(self):
  settings={**PROVIDER_SETTINGS,**ingress_proof(),'BURIMUNSI_NATIVE_ENABLED':'true',
            'BURIMUNSI_NATIVE_UPLOADS_ENABLED':'true','BURIMUNSI_NATIVE_WORKERS_ENABLED':'true'}
  root,_=self.fixture(settings=settings);status=configure(root)
  self.assertTrue(status['burimunsi_uploads_requested'])
  self.assertFalse(status['burimunsi_collection_verified'])
  self.assertEqual(read_env(root/'private/functions.env')['BURIMUNSI_COLLECTION_ID'],'')
  self.assert_no_native_public(root)
 def test_previous_provider_contract_defaults_only_new_upload_opt_in_off(self):
  settings=dict(PROVIDER_SETTINGS);del settings['BURIMUNSI_NATIVE_UPLOADS_ENABLED']
  root,_=self.fixture(settings=settings);before=(root/'private/provider-settings.json').read_bytes()
  status=configure(root)
  self.assertFalse(status['burimunsi_uploads_requested'])
  self.assertEqual((root/'private/provider-settings.json').read_bytes(),before)
  self.assertEqual(read_env(root/'private/functions.env')['BURIMUNSI_NATIVE_UPLOADS_ENABLED'],'false')
 def test_public_native_remnants_are_removed_and_web_uses_only_public_env(self):
  root,_=self.fixture();path=root/'public.env';values=read_env(path);values.update({'BURIMUNSI_PIN_PEPPER_BASE64':key(3),'BURIMUNSI_NATIVE_ENABLED':'true','BURIMUNSI_COLLECTION_ID':'private-group'});path.write_text(dotenv(values))
  configure(root);self.assert_no_native_public(root)
  compose=build_compose(PROFILE,verify_vendor())
  self.assertEqual(compose['services']['web']['env_file'],['./public.env'])
  self.assertEqual(compose['services']['functions']['env_file'],['./private/functions.env'])
  self.assertTrue(set(NATIVE_PRIVATE_KEYS).issubset(PRIVATE_KEYS))
  self.assertNotIn('BURIMUNSI_',json.dumps(compose['services']['web']))
 def test_ingress_missing_partial_changed_reused_keys_fail_before_any_projection(self):
  for change in [dict(COLLECT_NATIVE_INGRESS_KEY_BASE64=key(1)),dict(COLLECT_NATIVE_INGRESS_KEY_BASE64=key(2)),
   dict(COLLECT_NATIVE_INGRESS_KEY_BASE64=key(3)),dict(COLLECT_NATIVE_INGRESS_KEY_BASE64=key(4)),dict(COLLECT_NATIVE_INGRESS_KEY_ID='../bad')]:
   root,_=self.fixture(keys={**private_keys(),**change});before=self.outputs(root)
   with self.assertRaises(ValueError):configure(root)
   self.assertEqual(self.outputs(root),before)
  for missing in INGRESS_PRIVATE_KEYS:
   keys=private_keys();del keys[missing];root,_=self.fixture(keys=keys);before=self.outputs(root)
   with self.assertRaisesRegex(ValueError,'incomplete'):configure(root)
   self.assertEqual(self.outputs(root),before)
  keys={name:value for name,value in private_keys().items() if name not in INGRESS_PRIVATE_KEYS}
  root,_=self.fixture(keys=keys,settings={**PROVIDER_SETTINGS,**ingress_proof(),'BURIMUNSI_NATIVE_ENABLED':'true','BURIMUNSI_COLLECTION_ID':'existing-group'});before=self.outputs(root)
  with self.assertRaisesRegex(ValueError,'explicit retained-key'):configure(root)
  self.assertEqual(self.outputs(root),before)
 def test_ingress_enable_requires_exact_reviewed_profile_and_origin_worker_guard_evidence(self):
  for proof in [{},ingress_proof({'status':'observed'}),ingress_proof({'nativeWorkerGuard':'allow all'}),
   ingress_proof({'protectedUnixSocket':False}),ingress_proof({'pseudoIpv4':'overwrite'}),ingress_proof({'reviewedAt':int(time.time()*1000)+60000})]:
   root,_=self.fixture(settings={**PROVIDER_SETTINGS,**proof,'BURIMUNSI_NATIVE_ENABLED':'true','BURIMUNSI_COLLECTION_ID':'existing-group'});before=self.outputs(root)
   with self.assertRaisesRegex(ValueError,'ingress edge proof'):configure(root)
   self.assertEqual(self.outputs(root),before)
 def test_ingress_proof_configuration_remains_private_and_never_claims_live_edge_acceptance(self):
  root,_=self.fixture(settings={**PROVIDER_SETTINGS,**ingress_proof(),'BURIMUNSI_NATIVE_ENABLED':'true','BURIMUNSI_COLLECTION_ID':'existing-group'})
  values=read_env(root/'public.env');values['COLLECT_NATIVE_INGRESS_KEY_BASE64']=key(5);values.update(ingress_proof());(root/'public.env').write_text(dotenv(values))
  status=configure(root);self.assertTrue(status['burimunsi_ingress_review_record_configured']);self.assertFalse(status['burimunsi_live_edge_verified']);self.assertFalse(status['burimunsi_commissioned'])
  self.assert_no_native_public(root);self.assertTrue(set(INGRESS_PRIVATE_KEYS).issubset(PRIVATE_KEYS))
 def test_ingress_v2_review_has_no_waf_slot_or_expiring_authorization_timer(self):
  proof=ingress_proof({'reviewedAt':int(time.time()*1000)-366*86400000})
  record=json.loads(proof['COLLECT_NATIVE_INGRESS_EDGE_PROOF_JSON'])
  self.assertEqual(record['nativeWorkerGuard'],'origin_cf_worker_presence_reject')
  self.assertFalse({'expiresAt','nativeWorkerGuardRuleId','nativeWorkerGuardExpression'}&set(record))
  root,_=self.fixture(settings={**PROVIDER_SETTINGS,**proof,'BURIMUNSI_NATIVE_ENABLED':'true'})
  status=configure(root);self.assertTrue(status['burimunsi_ingress_review_record_configured'])
  self.assertFalse(status['burimunsi_live_edge_verified']);self.assertFalse(status['burimunsi_commissioned'])
 def test_ingress_v1_preserves_historical_record_without_expiry_outage(self):
  now=int(time.time()*1000)
  proof=ingress_proof({'format':'collect.native-ingress.edge-proof.v1','reviewedAt':now-3*86400000,'expiresAt':now-2*86400000})
  root,_=self.fixture(settings={**PROVIDER_SETTINGS,**proof,'BURIMUNSI_NATIVE_ENABLED':'true'})
  self.assertTrue(configure(root)['burimunsi_ingress_review_record_configured'])
  self.assertEqual(read_env(root/'private/functions.env')['COLLECT_NATIVE_INGRESS_EDGE_PROOF_JSON'],proof['COLLECT_NATIVE_INGRESS_EDGE_PROOF_JSON'])
  for invalid in [{'nativeWorkerGuardRuleId':''},{'nativeWorkerGuardExpression':'allow all'},{'expiresAt':now-4*86400000}]:
   broken=ingress_proof({'format':'collect.native-ingress.edge-proof.v1','reviewedAt':now-3*86400000,**invalid})
   with self.assertRaisesRegex(ValueError,'ingress edge proof'):
    validated_settings({**PROVIDER_SETTINGS,**broken,'BURIMUNSI_NATIVE_ENABLED':'true'},PROFILE,'a'*64)
 def test_explicit_frontdoor_export_contains_only_ingress_authority_and_preserves_every_sealed_input(self):
  root,_=self.fixture();configure(root)
  path=root/'private/functions.env';values=read_env(path)
  values.update({'COLLECT_DEPLOYMENT_PROFILE':canonical_profile(PROFILE),'COLLECT_DEPLOYMENT_PROFILE_SHA256':profile_sha256(PROFILE),
   'APP_ENVIRONMENT':PROFILE['environment'],'SUPABASE_URL':PROFILE['supabase_origin']})
  path.write_text(dotenv(values));seal_configuration(root);before=self.outputs(root);output=root/'private/ingress.env'
  with patch('scripts.self_hosted.prepare.subprocess.run') as command:
   result=export_native_ingress_environment(root,output,Path('/tmp/synthetic-native.sock'))
  command.assert_not_called();self.assertEqual(self.outputs(root),before);self.assertEqual(output.stat().st_mode&0o777,0o600)
  ingress=read_env(output);self.assertEqual(ingress['COLLECT_NATIVE_INGRESS_KEY_BASE64'],key(5));self.assertEqual(ingress['SUPABASE_INTERNAL_URL'],'http://127.0.0.1:55101')
  self.assertEqual(set(ingress),{'COLLECT_DEPLOYMENT_PROFILE','COLLECT_DEPLOYMENT_PROFILE_SHA256','APP_ENVIRONMENT','SUPABASE_URL','SUPABASE_INTERNAL_URL',
   'COLLECT_NATIVE_INGRESS_KEY_BASE64','COLLECT_NATIVE_INGRESS_KEY_ID','COLLECT_NATIVE_INGRESS_SOCKET',*INGRESS_CONTROLS,
   'BURIMUNSI_NATIVE_ENABLED','AUTH_PHONE_DELIVERY_MODE','AUTH_WHATSAPP_ENABLED'})
  for secret in (key(1),key(2),key(3),key(4),'retained-signing-$literal','retained-service-key'):self.assertNotIn(secret,output.read_text())
  self.assertFalse(result['commissioned']);self.assertFalse(result['native_requested']);self.assertEqual(result['environment_sha256'],hashlib.sha256(output.read_bytes()).hexdigest())
  self.assertEqual(result['configuration_sha256'],hashlib.sha256(before['private/configuration.json']).hexdigest())
  with self.assertRaises(FileExistsError):export_native_ingress_environment(root,output,Path('/tmp/synthetic-native.sock'))
  self.assertEqual(self.outputs(root),before)
 def test_frontdoor_export_refuses_unsealed_changes_and_unprotected_destination(self):
  root,_=self.fixture();configure(root);path=root/'private/functions.env';values=read_env(path)
  values.update({'COLLECT_DEPLOYMENT_PROFILE':canonical_profile(PROFILE),'COLLECT_DEPLOYMENT_PROFILE_SHA256':profile_sha256(PROFILE),
   'APP_ENVIRONMENT':PROFILE['environment'],'SUPABASE_URL':PROFILE['supabase_origin']});path.write_text(dotenv(values))
  output=root/'private/ingress.env'
  with self.assertRaises(ValueError):export_native_ingress_environment(root,output,Path('/tmp/synthetic-native.sock'))
  self.assertFalse(output.exists());seal_configuration(root);(root/'private').chmod(0o755)
  with self.assertRaises(ValueError):export_native_ingress_environment(root,output,Path('/tmp/synthetic-native.sock'))
  self.assertFalse(output.exists())

if __name__=='__main__':unittest.main()
