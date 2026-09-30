const test=require('node:test'),assert=require('node:assert/strict'),path=require('node:path');
const load=n=>require(path.join(process.env.COLLECT_COMPILED_MODULES,n+'.js'));
const c=load('production_contract'),{verifySmsHook}=load('signed_sms_hook'),{validateIntegrityVerdict}=load('integrity_policy');
const {validateRosterFile}=load('roster_file_policy'),{acceptReceipt}=load('receipt_ingestion'),{normalizeRwandaPhone,sha256Hex}=load('hash');
const owner='11111111-1111-4111-8111-111111111111',envelope='22222222-2222-4222-8222-222222222222',cap='33333333-3333-4333-8333-333333333333',raw='44444444-4444-4444-8444-444444444444';
const hash='a'.repeat(64);
for(const [input,expected] of [['0788123456','+250788123456'],['+250788123456','+250788123456'],['00250788123456','+250788123456'],['788123456','+250788123456'],[' 073 123 4567 ','+250731234567'],['+1 2025550123',null],['abc0788123456',null],['++250788123456',null],['+250000000000',null],['07881234567',null],['',null],[null,null],['25+0788123456',null]]){
 test('Rwanda phone: '+String(input),()=>assert.equal(normalizeRwandaPhone(input),expected));
}
for(const version of [null,undefined,0,1,3,'2',{},false]) test('Contract refuses '+String(version),()=>assert.throws(()=>c.requireReceiptContract(version)));
test('Contract accepts exact v2',()=>c.requireReceiptContract(2));
const ack={contract_version:2,stored:true,raw_sms_id:raw,owner_user_id:owner,client_envelope_id:envelope,body_sha256:hash};
test('ACK accepts exact bound evidence and strips unknown values',()=>assert.deepEqual(c.validateReceiptAck({...ack,unsafe:'private'},owner,envelope,hash),ack));
for(const change of [{stored:false},{contract_version:1},{raw_sms_id:''},{body_sha256:'0'.repeat(64)},{owner_user_id:cap},{client_envelope_id:raw}])test('ACK refuses '+Object.keys(change)[0],()=>assert.throws(()=>c.validateReceiptAck({...ack,...change},owner,envelope,hash)));
for(const value of ['2026-02-30T10:00:00Z','2026-01-01','2026-01-01T10:00:00','2026-01-01T25:00:00Z','2026-01-01T10:00:00Zjunk'])test('Timestamp refuses '+value,()=>assert.throws(()=>c.zonedInstant(value)));
test('Timestamp valid offset',()=>assert.equal(c.zonedInstant('2026-09-27T10:00:00+02:00'),'2026-09-27T10:00:00+02:00'));
test('Unknown timestamp stays null',()=>assert.equal(c.zonedInstant(null),null));
test('JSON preserves exact text',async()=>assert.deepEqual(await c.boundedJson(new Request('https://unit.test',{method:'POST',headers:{'content-type':'application/json'},body:'{"x":" é "}'})),{x:' é '}));
test('Stream bound cannot be bypassed by missing Content-Length',async()=>await assert.rejects(c.boundedBody(new Response('abcd'),3),{code:'payload_too_large'}));
test('Declared excessive Content-Length rejected',async()=>await assert.rejects(c.boundedBody(new Response('',{headers:{'content-length':'9000'}}),3),{code:'payload_too_large'}));
test('Invalid UTF8 rejected',async()=>await assert.rejects(c.boundedBody(new Response(new Uint8Array([255])),3),{code:'invalid_utf8'}));
test('Array JSON not object',async()=>await assert.rejects(c.boundedJson(new Request('https://unit.test',{method:'POST',headers:{'content-type':'application/json'},body:'[]'}))));
test('No JSON MIME rejected',async()=>await assert.rejects(c.boundedJson(new Request('https://unit.test',{method:'POST',body:'{}'})),{status:415}));
test('Private exception not exposed',()=>assert.deepEqual(c.publicFailure(new Error('token SECRET OTP 123456')),{error:'service_unavailable',status:503}));
const now=1800000000,secret=Buffer.alloc(32,7).toString('base64');
async function hook({body='{"user":{"phone":"+250788123456"},"sms":{"otp":"123456"}}',time=now,id='msg_a',signedBody=body,key=secret,signature,extra={}}={}){
 const signed=await crypto.subtle.importKey('raw',Buffer.from(key,'base64'),{name:'HMAC',hash:'SHA-256'},false,['sign']);
 const sig=Buffer.from(await crypto.subtle.sign('HMAC',signed,new TextEncoder().encode(`${id}.${time}.${signedBody}`))).toString('base64');
 return new Request('https://unit.test',{method:'POST',headers:{'webhook-id':id,'webhook-timestamp':String(time),'webhook-signature':signature??'v1,'+sig,...extra},body});
}
test('Signed webhook exact body passes',async()=>assert.equal((await verifySmsHook(await hook(),['v1,whsec_'+secret],now)).id,'msg_a'));
test('Previous key rotation passes',async()=>assert.ok(await verifySmsHook(await hook(),[Buffer.alloc(32,8).toString('base64'),secret],now)));
for(const [name,args] of [['body modified',{signedBody:'different'}],['past expired',{time:now-301}],['future expired',{time:now+301}],['bad id',{id:'a\tb'}],['no signature',{signature:''}],['wrong signature',{signature:'v1,'+Buffer.alloc(32).toString('base64')}]] )test('Signed webhook rejects '+name,async()=>await assert.rejects(verifySmsHook(await hook(args),[secret],now)));
test('Static header is not auth',async()=>await assert.rejects(verifySmsHook(new Request('https://unit.test',{method:'POST',headers:{'x-hook-secret':secret},body:'{}'}),[secret],now)));
const policy={packageName:'app.cool.mobile',minimumVersion:23,certificates:new Set(['CERT']),nowMs:now*1000};
const verdict=()=>({requestDetails:{requestPackageName:'app.cool.mobile',requestHash:hash,timestampMillis:String(now*1000)},appIntegrity:{packageName:'app.cool.mobile',appRecognitionVerdict:'PLAY_RECOGNIZED',versionCode:'23',certificateSha256Digest:['CERT']},accountDetails:{appLicensingVerdict:'LICENSED'},deviceIntegrity:{deviceRecognitionVerdict:['MEETS_DEVICE_INTEGRITY']}});
test('Integrity accepts configured licensed build',()=>assert.equal(validateIntegrityVerdict(verdict(),hash,policy).appVerdict,'PLAY_RECOGNIZED'));
for(const [section,key,value] of [['accountDetails','appLicensingVerdict','UNLICENSED'],['appIntegrity','versionCode','22'],['appIntegrity','certificateSha256Digest',['OTHER']],['requestDetails','requestHash','b'.repeat(64)],['requestDetails','requestPackageName','other'],['requestDetails','timestampMillis',String(now*1000+31000)],['deviceIntegrity','deviceRecognitionVerdict',[]]])test('Integrity rejects '+key,()=>{const v=verdict();v[section][key]=value;assert.throws(()=>validateIntegrityVerdict(v,hash,policy));});
test('Integrity missing configuration blocks',()=>assert.throws(()=>validateIntegrityVerdict(verdict(),hash,{...policy,certificates:new Set()})));
test('Roster truncated PDF signature rejected',()=>assert.throws(()=>validateRosterFile(Buffer.from('%PDF-1.7\n'),'application/pdf')));
test('Roster spoofed PDF rejected',()=>assert.throws(()=>validateRosterFile(Buffer.from('<html>payload</html>'),'application/pdf')));
test('Roster oversized rejected',()=>assert.throws(()=>validateRosterFile(new Uint8Array(5*1024*1024+1),'application/pdf')));
test('Roster truncated WebP signature rejected',()=>assert.throws(()=>validateRosterFile(Buffer.from('RIFF....WEBPdata'),'image/webp')));
test('PNG bomb dimensions rejected',()=>{const b=Buffer.alloc(24);Buffer.from([137,80,78,71,13,10,26,10]).copy(b);b.write('IHDR',12);b.writeUInt32BE(16000,16);b.writeUInt32BE(16000,20);assert.throws(()=>validateRosterFile(b,'image/png'));});
const receiptBody={raw_body:'  receipt body é  ',raw_sender:'M-Money',client_envelope_id:envelope,native_capability:cap,receiver_momo_number:'+250788123456',received_at_device:'2026-09-27T10:00:00Z'};
const request=(patch={})=>new Request('https://unit.test',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({...receiptBody,...patch})});
function deps(patch={}){const calls=[];return {calls,owner:async()=>owner,version:async()=>2,accept:async p=>{calls.push(p);return {...ack,body_sha256:p.p_body_hash};},process:async()=>true,...patch};}
test('Receipt orchestrator uses unchanged body and exact durable ACK',async()=>{const d=deps();const r=await acceptReceipt(request(),d);assert.equal(d.calls[0].p_raw_body,receiptBody.raw_body);assert.equal(r.body_sha256,await sha256Hex(receiptBody.raw_body));});
test('Receipt legacy contract never invokes storage',async()=>{const d=deps({version:async()=>1});await assert.rejects(acceptReceipt(request(),d));assert.equal(d.calls.length,0);});
test('Receipt auth failure never invokes storage',async()=>{const d=deps({owner:async()=>{throw new Error('Authentication required')}});await assert.rejects(acceptReceipt(request(),d));assert.equal(d.calls.length,0);});
test('Receipt wrong ACK owner never processed',async()=>{let processed=false;const d=deps({accept:async()=>({...ack,owner_user_id:cap}),process:async()=>{processed=true;return true;}});await assert.rejects(acceptReceipt(request(),d));assert.equal(processed,false);});
test('Receipt uncertain parsing returns error, not ACK',async()=>{const d=deps({process:async()=>false});await assert.rejects(acceptReceipt(request(),d),{code:'receipt_stored_processing_retry'});assert.equal(d.calls.length,1);});
test('Receipt unknown version does not downgrade on lookup failure',async()=>{const d=deps({version:async()=>{throw new Error('RPC missing')}});await assert.rejects(acceptReceipt(request(),d));assert.equal(d.calls.length,0);});
test('Receipt invalid receiver rejected before storage',async()=>{const d=deps();await assert.rejects(acceptReceipt(request({receiver_momo_number:'+12025550123'}),d));assert.equal(d.calls.length,0);});
