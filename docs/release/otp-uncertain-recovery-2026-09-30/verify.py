#!/usr/bin/env python3
"""Local OTP verification only. No SQL execution, provider calls or deployment."""
import ast,datetime,hashlib,json,os,pathlib,re,shutil,subprocess,sys
ROOT=pathlib.Path(__file__).resolve().parents[3]
PACKET=pathlib.Path(__file__).resolve().parent
OUT=PACKET/'pinned-validation'
if OUT.exists():raise SystemExit('Preserve dated logs: pinned-validation already exists')
OUT.mkdir()
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
owned=['supabase/functions/auth-send-whatsapp-otp/index.ts','supabase/functions/auth-send-whatsapp-otp/handler.ts',
 'supabase/functions/auth-send-whatsapp-otp/handler_test.ts','supabase/functions/_shared/cors.ts','supabase/functions/_shared/hash.ts',
 'supabase/functions/_shared/signed_sms_hook.ts','supabase/functions/_shared/production_contract.ts','supabase/functions/_shared/supabase.ts',
 'supabase/functions/_shared/test_assert.ts','supabase/migrations/20260930130000_signed_otp_uncertain_recovery.sql',
 'scripts/tests/signed_otp_recovery_uat.sql','scripts/tests/signed_otp_recovery_concurrency_uat.rb',
 'scripts/tests/signed_otp_recovery_upgrade_uat.py','deploy/hardening/signed_otp_limits_v2.sql',
 'scripts/hardening/edge_http.test.cjs','scripts/hardening/roster_http.test.cjs','scripts/hardening/run_edge_http_tests.py',
 'scripts/hardening/source_integration_test.py','docs/release/otp-uncertain-recovery-2026-09-30/sdk.lock',
 'docs/release/otp-uncertain-recovery-2026-09-30/sources/legacy-signed-otp-limits-v2.sql',
 'docs/release/otp-uncertain-recovery-2026-09-30/verify.py']
# Bind actual modules copied by the existing HTTP harness and its static suite.
tree=ast.parse((ROOT/'scripts/hardening/run_edge_http_tests.py').read_text())
for n in ast.walk(tree):
 if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='modules' for t in n.targets):
  owned += ['supabase/functions/_shared/'+v+'.ts' for v in ast.literal_eval(n.value)]
 if isinstance(n,ast.For) and isinstance(n.iter,ast.List):
  values=ast.literal_eval(n.iter)
  if isinstance(n.target,ast.Name) and n.target.id=='name':owned+=['supabase/functions/'+v+'/index.ts' for v in values]
  if isinstance(n.target,ast.Name) and n.target.id=='module':owned+=['supabase/functions/'+v for v in values]
for name in re.findall(r"source\('([^']+)'\)",(ROOT/'scripts/hardening/source_integration_test.py').read_text()):owned.append(name)
owned=sorted(set(owned))
before={p:digest(ROOT/p) for p in owned}
deno=ROOT/'.cache/roster-deno-2.5.6-20260929/deno'
env=os.environ.copy();env['DENO_DIR']=str(ROOT/'.cache/otp-deno-sdk-20260930')
commands=[
 ('handler-tests',[str(deno),'test','--no-prompt','supabase/functions/auth-send-whatsapp-otp/handler_test.ts']),
 ('real-sdk-typecheck',[str(deno),'check','--frozen','--lock=docs/release/otp-uncertain-recovery-2026-09-30/sdk.lock','supabase/functions/auth-send-whatsapp-otp/index.ts','supabase/functions/auth-send-whatsapp-otp/handler_test.ts']),
 ('otp-lint',[str(deno),'lint','supabase/functions/auth-send-whatsapp-otp']),
 ('otp-format',[str(deno),'fmt','--check','supabase/functions/auth-send-whatsapp-otp']),
 ('full-mocked-http',[sys.executable,'scripts/hardening/run_edge_http_tests.py']),
 ('static-integration',[sys.executable,'scripts/hardening/source_integration_test.py']),
 ('concurrency-syntax',['ruby','-c','scripts/tests/signed_otp_recovery_concurrency_uat.rb']),
 ('upgrade-emitter',[sys.executable,'scripts/tests/signed_otp_recovery_upgrade_uat.py','--emit-source-only','--migration-sha256',before['supabase/migrations/20260930130000_signed_otp_uncertain_recovery.sql']]),
]
runs=[]
for name,cmd in commands:
 start=datetime.datetime.now(datetime.timezone.utc).isoformat()
 r=subprocess.run(cmd,cwd=ROOT,env=env,capture_output=True,timeout=90)
 (OUT/(name+'.stdout')).write_bytes(r.stdout);(OUT/(name+'.stderr')).write_bytes(r.stderr)
 runs.append({'name':name,'command':cmd,'started_at_utc':start,'exit_code':r.returncode,
  'stdout_sha256':digest(OUT/(name+'.stdout')),'stderr_sha256':digest(OUT/(name+'.stderr'))})
after={p:digest(ROOT/p) for p in owned}
tools={}
for name,binary,versioncmd in [('deno',deno,[str(deno),'--version']),('bun',pathlib.Path(shutil.which('bun')),['bun','--version']),
 ('python',pathlib.Path(sys.executable),[sys.executable,'--version']),('ruby',pathlib.Path(shutil.which('ruby')),['ruby','--version'])]:
 tools[name]={'path':str(binary.resolve()),'sha256':digest(binary.resolve()),'version':subprocess.run(versioncmd,capture_output=True,text=True).stdout.strip()}
result={'pass':all(r['exit_code']==0 for r in runs) and before==after,'captured_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'verified_scope':'local signed OTP HTTP handler, mocked dependencies, actual pinned SDK typecheck and source-only SQL preparation',
 'source_count':len(owned),'sources_before':before,'sources_after':after,'source_stable':before==after,'runs':runs,'toolchains':tools,
 'test_counts':{'otp_mocked_deno':53,'shared_mocked_http':55,'static_integration':16},
 'sql_runtime_executed':False,'provider_delivery_verified':False,'database_mutations':0,
 'remaining':['Root local migration145 apply/reapply and staged-v2 upgrade rehearsal','Root rollback SQL UAT','Root guarded real two-session concurrency harness','Final-set clean/populated integration rehearsal']}
(PACKET/'verification.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({k:result[k] for k in ['pass','source_count','source_stable','test_counts','sql_runtime_executed']}))
raise SystemExit(0 if result['pass'] else 1)
