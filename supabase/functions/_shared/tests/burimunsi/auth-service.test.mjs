import test from 'node:test';import assert from 'node:assert/strict';
import {NativeAuthService} from '../../domain/burimunsi/auth-service.js';
import {PinHasher} from '../../domain/burimunsi/pin.js';
import {sha256} from '../../domain/burimunsi/values.js';
const NOW=1793961600000,G='group-1',I='5ac17356-3e19-4d79-87ae-2ef65a42ff14',D='a'.repeat(64),N='b'.repeat(64);
// TEST ONLY: finite state adapter. Production uses qualified PostgreSQL transactions.
class Store{
 constructor(){this.a={id:'11111111-1111-4111-8111-111111111111',groupId:G,name:'Example Admin',phone:'+250780000001',role:'admin',capabilities:['records.read','members.enroll','payments.allocate','staff.manage'],active:true,removed:false,credentialVersion:1,version:1,pinHash:{phone:'+250780000001',pin:'0123'}};this.accounts=[this.a];this.device={id:'88888888-8888-4888-8888-888888888888',active:true,version:1,accountIds:[this.a.id]};this.sessions=[];this.windows=new Map();this.receipts=new Map();this.race=false;this.writes=0;}
 async consumeAttempts(buckets,now){let allow=true;for(const b of buckets){const key=b.key+':'+Math.floor(now/b.windowMs),n=(this.windows.get(key)||0)+1;this.windows.set(key,n);if(n>b.limit)allow=false;}return allow;}
 async findAccount(g,p){return this.accounts.find(a=>a.groupId===g&&a.phone===p);}
 async findStaff(g,id){return this.accounts.find(a=>a.groupId===g&&a.id===id);}
 async findDeviceGrant(g,i,hash){return g===G&&i===I&&hash===await sha256(D)?this.device:null;}
 async createSessionIfCurrent(s){if(this.race||this.a.credentialVersion!==s.credentialVersion)return false;this.sessions.push({...s,revoked:false});return true;}
 async loadSession(hash,i,now){const s=this.sessions.find(s=>s.tokenHash===hash&&s.installationId===i&&!s.revoked&&s.expiresAt>now);if(!s||!this.device.active||s.deviceGrantVersion!==this.device.version||!this.a.active||this.a.removed||this.a.credentialVersion!==s.credentialVersion)return null;return {...this.a,sessionId:s.id,installationId:i,expiresAt:s.expiresAt};}
 async revokeSession(id){this.sessions.filter(s=>s.id===id).forEach(s=>s.revoked=true);}
 async changePinIfCurrent(c){const a=this.accounts.find(a=>a.id===c.accountId),old=this.sessions.find(s=>s.id===c.sessionId&&!s.revoked);
  if(!a||!old||a.credentialVersion!==c.expectedCredentialVersion||a.version!==c.expectedAccountVersion||this.race)return false;
  a.pinHash=c.pinHash;a.credentialVersion++;a.version++;this.sessions.forEach(s=>{if(s.accountId===a.id)s.revoked=true});
  const expiresAt=NOW+c.sessionTtlMs;this.sessions.push({...old,id:crypto.randomUUID(),tokenHash:c.replacementTokenHash,
   credentialVersion:a.credentialVersion,expiresAt,revoked:false});return {rotated:true,expiresAt};}
 async retainedStaffCommand(c){return this.receipts.get(c.requestId)||null;}
 async mutateStaff(c){this.writes++;let a=this.accounts.find(x=>x.id===c.id);if(c.action==='create'){a={id:crypto.randomUUID(),groupId:G,role:'staff',active:true,removed:false,version:1,credentialVersion:1,...c};delete a.action;this.accounts.push(a);}else{if(!a||a.version!==c.expectedVersion)return {applied:false};Object.assign(a,c);a.version++;if(c.action==='disable'||c.action==='remove')a.active=false;if(c.action==='enable')a.active=true;if(c.action==='remove')a.removed=true;}const response={applied:true,id:a.id,version:a.version};this.receipts.set(c.requestId,{sessionId:c.actorSessionId,fingerprint:c.fingerprint,response});return response;}
}
const hasher={hash:async(phone,pin)=>({phone,pin}),verify:async(phone,pin,r)=>r.phone===phone&&r.pin===pin,commandFingerprint:async value=>sha256('test-only-keyed-boundary:'+value)};
function setup(extra={}){const store=new Store(),svc=new NativeAuthService({store,hasher,groupId:G,clock:()=>NOW,...extra});return {store,svc};}
const login={phone:'0780000001',pin:'0123',installationId:I,installationToken:D};
async function signed(extra={}){const env=setup(extra),response=await env.svc.login(login,N),actor=await env.svc.authenticate(response.token,I);return {...env,response,actor};}
test('session creation retains exact grant identity and presented token proof',async()=>{const {svc,store}=setup();await svc.login(login,N);assert.equal(store.sessions[0].deviceGrantId,store.device.id);assert.equal(store.sessions[0].deviceTokenHash,await sha256(D));assert.notEqual(store.sessions[0].tokenHash,await sha256(D));});
test('assigned phone and four-digit PIN create an opaque scoped session',async()=>{const {response,actor}=await signed();assert.match(response.token,/^[a-f0-9]{64}$/);assert.equal(actor.phone,'+250780000001');assert.equal(actor.groupId,G);assert.equal(response.profile.pinHash,undefined)});
for(const bad of [{pin:'123'},{pin:'12345'},{phone:'staff@example.org'},{pin:1234}])test('reject malformed login '+JSON.stringify(bad),async()=>{const {svc}=setup();await assert.rejects(svc.login({...login,...bad},N))});
for(const [field,value]of [['phone','0780000999'],['pin','9999'],['installationId','another-device'],['installationToken','c'.repeat(64)]])test('generic credential failure '+field,async()=>{const {svc}=setup();await assert.rejects(svc.login({...login,[field]:value},N),e=>e.code==='invalid_credentials'&&e.status===401)});
test('success does not reset distributed account attempt counter',async()=>{const {svc}=setup();for(let i=0;i<5;i++)await svc.login(login,N);await assert.rejects(svc.login(login,N),e=>e.status===429)});
test('untrusted network identifier rejected before login',async()=>{const {svc}=setup();await assert.rejects(svc.login(login,'client-ip'))});
test('credential change racing session creation denies sign-in',async()=>{const {svc,store}=setup();store.race=true;await assert.rejects(svc.login(login,N),/invalid_credentials/)});
for(const change of ['revoke','expire','deviceVersion','credentialVersion','disabledAccount','disabledDevice'])test('session revalidation '+change,async()=>{const {svc,store,response,actor}=await signed();if(change==='revoke')await svc.logout(actor);if(change==='expire')store.sessions[0].expiresAt=NOW;if(change==='deviceVersion')store.device.version++;if(change==='credentialVersion')store.a.credentialVersion++;if(change==='disabledAccount')store.a.active=false;if(change==='disabledDevice')store.device.active=false;await assert.rejects(svc.authenticate(response.token,I))});
test('session cannot be moved to another installation',async()=>{const {svc,response}=await signed();await assert.rejects(svc.authenticate(response.token,'other-device'))});
test('own PIN change rotates to the candidate device session and revokes all old sessions',async()=>{const {svc,store,actor,response}=await signed();
 const other=await svc.login(login,N),replacementToken='e'.repeat(64);
 const result=await svc.changePasscode(actor,{current:'0123',newPin:'0007',confirm:'0007',replacementToken});
 assert.deepEqual(result,{reauthenticationRequired:false,expiresAt:NOW+1800000});assert.equal(store.a.pinHash.pin,'0007');
 await assert.rejects(svc.authenticate(response.token,I));await assert.rejects(svc.authenticate(other.token,I));
 assert.equal((await svc.authenticate(replacementToken,I)).id,actor.id);assert.equal(store.sessions.filter(s=>!s.revoked).length,1);
 assert.equal(JSON.stringify(result).includes(replacementToken),false);await svc.login({...login,pin:'0007'},N)});
test('confirmation mismatch performs no credential write',async()=>{const {svc,store,actor}=await signed();await assert.rejects(svc.changePasscode(actor,{current:'0123',newPin:'0007',confirm:'0008'}),/passcodes_do_not_match/);assert.equal(store.a.credentialVersion,1)});
test('wrong current PIN is a definite rejection and preserves the authenticated session',async()=>{const {svc,store,actor,response}=await signed();
 await assert.rejects(svc.changePasscode(actor,{current:'9999',newPin:'0007',confirm:'0007',replacementToken:'e'.repeat(64)}),
  e=>e.code==='invalid_current_pin'&&e.status===400);assert.equal(store.a.credentialVersion,1);assert.equal((await svc.authenticate(response.token,I)).id,actor.id)});
test('unchanged PIN or malformed candidate produces no credential write',async()=>{for(const [current,newPin,token] of [['0123','0123','e'.repeat(64)],['0123','0007','bad']]){
 const {svc,store,actor,response}=await signed();await assert.rejects(svc.changePasscode(actor,{current,newPin,confirm:newPin,replacementToken:token}));
 assert.equal(store.a.credentialVersion,1);assert.equal((await svc.authenticate(response.token,I)).id,actor.id);}});
test('logout or account-version change before commit cannot create a replacement session',async()=>{for(const race of ['logout','version']){
 const {svc,store,actor}=await signed(),find=store.findAccount.bind(store);store.findAccount=async(...args)=>{const account=await find(...args);
  const snapshot={...account};if(race==='logout')await store.revokeSession(actor.sessionId);else store.a.version++;return snapshot;};
 await assert.rejects(svc.changePasscode(actor,{current:'0123',newPin:'0007',confirm:'0007',replacementToken:'e'.repeat(64)}));
 const candidateHash=await sha256('e'.repeat(64));assert.equal(store.sessions.some(s=>!s.revoked&&s.tokenHash===candidateHash),false);assert.equal(store.a.pinHash.pin,'0123');}});
const create=()=>({action:'create',name:'Example Staff',phone:'0780000002',pin:'0042',capabilities:['records.read','members.enroll'],requestId:crypto.randomUUID()});
test('admin adds staff without returning credential material',async()=>{const {svc,store,actor}=await signed();const result=await svc.manageStaff(actor,create());assert.deepEqual(Object.keys(result).sort(),['applied','id','version']);assert.equal(store.accounts[1].role,'staff');assert.equal(store.accounts[1].phone,'+250780000002')});
test('admin can use the protected configured default for a new staff account',async()=>{
 const {svc,store,actor}=await signed({defaultStaffPin:'1357'}),command=create();delete command.pin;
 const result=await svc.manageStaff(actor,command);
 assert.equal(store.accounts[1].pinHash.pin,'1357');assert.equal(store.accounts[1].pinHash.phone,'+250780000002');
 assert.equal(JSON.stringify(result).includes('1357'),false);assert.equal(store.writes,1);
 assert.deepEqual(await svc.manageStaff(actor,command),result);assert.equal(store.writes,1);
 svc.defaultStaffPin='2468';await assert.rejects(svc.manageStaff(actor,command),/idempotency_conflict/);assert.equal(store.writes,1);
});
test('a missing configured default fails before staff creation and staff cannot invoke it',async()=>{
 const {svc,store,actor}=await signed(),command=create();delete command.pin;
 await assert.rejects(svc.manageStaff(actor,command),e=>e.code==='staff_default_passcode_unconfigured'&&e.status===503);
 await assert.rejects(svc.manageStaff({...actor,role:'staff'},command),/access_denied/);assert.equal(store.writes,0);
});
test('an explicit staff passcode overrides the configured default',async()=>{
 const {svc,store,actor}=await signed({defaultStaffPin:'1357'});await svc.manageStaff(actor,create());
 assert.equal(store.accounts[1].pinHash.pin,'0042');
});
test('staff cannot manage another account',async()=>{const {svc,actor}=await signed();await assert.rejects(svc.manageStaff({...actor,role:'staff'},create()),/access_denied/)});
test('cannot smuggle admin role through creation',async()=>{const {svc,actor}=await signed();await assert.rejects(svc.manageStaff(actor,{...create(),role:'admin'}),/invalid_request/)});
test('cannot grant staff SMS capability',async()=>{const {svc,actor}=await signed();await assert.rejects(svc.manageStaff(actor,{...create(),capabilities:['records.read','sms.read']}),/access_denied/)});
test('credential command replay uses a keyed digest and no second write',async()=>{const {svc,store,actor}=await signed();const c=create();assert.deepEqual(await svc.manageStaff(actor,c),await svc.manageStaff(actor,c));assert.equal(store.writes,1)});
test('credential command replay from another session denied',async()=>{const {svc,actor}=await signed();const c=create();await svc.manageStaff(actor,c);await assert.rejects(svc.manageStaff({...actor,sessionId:crypto.randomUUID()},c),/idempotency_conflict/)});
test('staff login phone change requires an explicit replacement PIN',async()=>{const {svc,actor}=await signed();const a=await svc.manageStaff(actor,create());await assert.rejects(svc.manageStaff(actor,{action:'edit',id:a.id,expectedVersion:1,phone:'0780000003',requestId:crypto.randomUUID()}),/new_passcode_required/)});
test('opted-in staff phone edit requests protected PIN retention without accepting a client-supplied hash',async()=>{
 const {svc,store,actor}=await signed({preserveStaffPinOnPhoneChange:true});const a=await svc.manageStaff(actor,create());
 const original=store.mutateStaff.bind(store);let observed;store.mutateStaff=async c=>{observed=c;return original(c);};
 const result=await svc.manageStaff(actor,{action:'edit',id:a.id,expectedVersion:1,phone:'0780000003',requestId:crypto.randomUUID()});
 assert.equal(observed.retainPhoneBoundPin,true);assert.equal(Object.hasOwn(observed,'pinHash'),false);assert.equal(Object.hasOwn(result,'pinHash'),false);
});
test('the admin account cannot be removed by staff-lifecycle commands',async()=>{const {svc,actor}=await signed();await assert.rejects(svc.manageStaff(actor,{action:'remove',id:actor.id,expectedVersion:1,requestId:crypto.randomUUID()}),/staff_unavailable/)});
test('real HMAC/PBKDF2 credential path passes assigned phone authentication',async()=>{const real=new PinHasher({pepper:new Uint8Array(32).fill(17),pepperId:'test-pepper'});const {svc,store}=setup({hasher:real});store.a.pinHash=await real.hash(store.a.phone,'0123');const session=await svc.login(login,N);assert.equal((await svc.authenticate(session.token,I)).id,store.a.id)});
