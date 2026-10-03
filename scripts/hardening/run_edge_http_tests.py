#!/usr/bin/env python3
"""Execute the real OTP/receipt handlers with a minimal Deno-host adapter and
isolated Supabase/HTTP dependencies. Not a deployment or live integration test.
"""
import pathlib,tempfile,subprocess,re,os,argparse,shutil
p=argparse.ArgumentParser();p.add_argument('--output');a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[2]
modules=['production_contract','signed_sms_hook','hash','receipt_ingestion','cors','integrity_policy','integrity_admission','play_integrity_binding','momo_sms_parser','notification_operator','operational_metrics','roster_import','roster_file_policy','roster_response_policy','openai_roster','roster_provenance','roster_decoder','roster_resource_budget']
with tempfile.TemporaryDirectory(prefix='collect-edge-') as temp:
    w=pathlib.Path(temp);shared=w/'_shared';shared.mkdir()
    paths=[]
    has_tsc=shutil.which('tsc') is not None
    for name in modules:
        source=(root/'supabase/functions/_shared'/f'{name}.ts').read_text()
        target=shared/f'{name}.ts';target.write_text(re.sub(r'(from\s+[\'"][^\'"\n]+)\.ts([\'"])',r'\1.js\2',source) if has_tsc else source);paths.append(target)
    (shared/'supabase.ts').write_text('''export function serviceClient(): any { return (globalThis as any).__service; }
export async function requireUser(authorization:string|null):Promise<{user:{id:string};supabase:any}> { if (!authorization) throw new Error('Authentication required');return {user:(globalThis as any).__user.user,supabase:(globalThis as any).__service}; }
export function requireInternalRequest(request:Request):void { if(request.headers.get('x-collect-signature') !== 'test-only-internal') throw new Error('Internal function authorization failed'); }
''');paths.append(shared/'supabase.ts')
    (shared/'apns.ts').write_text('''export type ApnsCredentials = any;
export async function createApnsJwt(..._args:any[]):Promise<string> { return 'unit-token'; }
export async function sendApnsMessage(..._args:any[]):Promise<any> { throw new Error('provider not invoked in error tests'); }
''');paths.append(shared/'apns.ts')
    (shared/'fcm.ts').write_text('''export type FcmCredentials = any;
export async function createFcmAccessToken(..._args:any[]):Promise<string> { return 'unit-token'; }
export async function sendFcmMessage(..._args:any[]):Promise<any> { const send=(globalThis as any).__pushSend; if(send)return send();throw new Error('provider not invoked in error tests'); }
''');paths.append(shared/'fcm.ts')
    for name in ['auth-send-whatsapp-otp','ingest-payment-sms','parse-payment-sms','verify-play-integrity','send-notification','dispatch-notifications','collect-notification-operator','prepare-roster-import']:
        target=w/name/'index.ts';target.parent.mkdir()
        content=(root/f'supabase/functions/{name}/index.ts').read_text()
        target.write_text(re.sub(r'(from\s+[\'"][^\'"\n]+)\.ts([\'"])',r'\1.js\2',content) if has_tsc else content);paths.append(target)
    for module in ['auth-send-whatsapp-otp/handler.ts','dispatch-notifications/dispatcher.ts','send-notification/handler.ts','prepare-roster-import/handler.ts']:
        target=w/module
        content=(root/'supabase/functions'/module).read_text()
        target.write_text(re.sub(r'(from\s+[\'"][^\'"\n]+)\.ts([\'"])',r'\1.js\2',content) if has_tsc else content);paths.append(target)
    d=w/'host.d.ts';d.write_text('declare namespace Deno {const env:{get(name:string):string|undefined}; function serve(handler:(request:Request)=>Promise<Response>):void;}');paths.append(d)
    if has_tsc:
        build=subprocess.run(['tsc','--strict','--target','ES2022','--module','commonjs','--lib','ES2022,DOM','--outDir',str(w/'build'),*[str(x) for x in paths]],capture_output=True,text=True)
        if build.returncode:print(build.stdout+build.stderr);raise SystemExit(build.returncode)
    else:
        # These node:test suites share mutable host doubles and require Node's
        # sequential test semantics. Bun only transpiles the isolated copies.
        build=subprocess.run(['bun','build','--target=node','--format=cjs','--root',str(w),'--outdir',str(w/'build'),
                              *[str(x) for x in paths if x.name!='host.d.ts']],capture_output=True,text=True)
        if build.returncode:print(build.stdout+build.stderr);raise SystemExit(build.returncode)
    env=os.environ.copy();env['COLLECT_EDGE_BUILD']=str(w/'build')
    command=['node','--test']
    if has_tsc:
        preface='Strict handler compilation with declared host/dependency adapters: PASS\n'
    else:
        preface='TypeScript compiler unavailable; Bun transpilation and sequential Node host-adapter execution only (no type-check):\n'
    output=preface
    exit_code=0
    # Separate processes keep the suites' global host/HTTP doubles isolated.
    for suite in ['edge_http.test.cjs','roster_http.test.cjs']:
        run=subprocess.run([*command,str(root/'scripts/hardening'/suite)],env=env,capture_output=True,text=True)
        output+=run.stdout+run.stderr
        if run.returncode:exit_code=run.returncode
    print(output)
    if a.output:pathlib.Path(a.output).write_text(output)
    raise SystemExit(exit_code)
