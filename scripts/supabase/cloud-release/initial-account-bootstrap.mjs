// Preparation and fixed SQL body only; caller owns the reviewed fenced
// transaction and performs no writes merely by importing this module.
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {PinHasher} from '../../../supabase/functions/_shared/domain/burimunsi/pin.js';
import {normalizePhone,requirePin} from '../../../supabase/functions/_shared/domain/burimunsi/values.js';
import {management} from './access.mjs';

export const INITIAL_BOOTSTRAP_SQL_SHA256='8b8e1ddffd441a490b969875f10d8cc6e7b33a2fd5b6d806bcf56a99fee5a226';
export const INITIAL_BOOTSTRAP_EXTRA_RELATIONS=Object.freeze(['private.burimunsi_operator_approvals','private.burimunsi_native_staff_delegations']);
const sha=x=>createHash('sha256').update(x).digest('hex');
const uuid=x=>typeof x==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(x);
const hex=x=>typeof x==='string'&&/^[a-f0-9]{64}$/.test(x);
const cleanId=x=>typeof x==='string'&&/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(x);

// Explicit values stay private in this instance. JSON/debug formatting emits
// only the operation identity, never phones, PINs or credential hashes.
class InitialBootstrapInput {
 #row;
 constructor(row){this.#row=row;}
 toJSON(){return {operationId:this.#row.operationId,prepared:true};}
 row(){return {...this.#row};}
}
export async function prepareInitialBootstrap(input,{cloudRows,pepperRecord}={}){
 if(!input||!uuid(input.operationId)||!uuid(input.fenceOperationId)||!uuid(input.adminAccountId)||!uuid(input.staffAccountId)||
  !uuid(input.ownerPrincipalId)||!cleanId(input.collectionId)||!hex(input.sourceSha256)||!hex(input.authorizationSha256)||
  !Number.isSafeInteger(input.epoch)||input.epoch<1||input.adminAccountId===input.staffAccountId)throw Error('bootstrap_input_invalid');
 let adminPhone,staffPhone;
 try{adminPhone=normalizePhone(input.adminPhone);staffPhone=normalizePhone(input.staffPhone);requirePin(input.adminPin);requirePin(input.staffPin);}
 catch{throw Error('bootstrap_input_invalid');}
 if(adminPhone===staffPhone)throw Error('bootstrap_input_invalid');
 cloudRows??=(await management('secrets')).json();
 pepperRecord??={pepper:process.env.BURIMUNSI_PIN_PEPPER_BASE64,pepperId:process.env.BURIMUNSI_PIN_PEPPER_ID};
 const cloud=new Map(cloudRows.map(x=>[x.name,x.value]));
 const p=pepperRecord.pepper,id=pepperRecord.pepperId;
 if(typeof p!=='string'||typeof id!=='string'||! /^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/.test(id)||
  cloud.get('BURIMUNSI_PIN_PEPPER_BASE64')!==sha(p)||cloud.get('BURIMUNSI_PIN_PEPPER_ID')!==sha(id))throw Error('cloud_pepper_identity_unverified');
 const bytes=Buffer.from(p,'base64');
 if(bytes.length<32||bytes.length>256||bytes.toString('base64')!==p)throw Error('source_pepper_invalid');
 try{
  const hasher=new PinHasher({pepper:bytes,pepperId:id});
  const [adminPinHash,staffPinHash]=await Promise.all([hasher.hash(adminPhone,input.adminPin),hasher.hash(staffPhone,input.staffPin)]);
  return new InitialBootstrapInput({operationId:input.operationId,fenceOperationId:input.fenceOperationId,epoch:input.epoch,
   sourceSha256:input.sourceSha256,authorizationSha256:input.authorizationSha256,ownerPrincipalId:input.ownerPrincipalId,
   collectionId:input.collectionId,adminAccountId:input.adminAccountId,staffAccountId:input.staffAccountId,
   adminPhone,staffPhone,adminPinHash,staffPinHash,pepperId:id});
 }finally{bytes.fill(0);}
}

export async function confirmDefaultStaffPin(pin,{cloudRows}={}){
 try{requirePin(pin);}catch{throw Error('bootstrap_input_invalid');}
 cloudRows??=(await management('secrets')).json();
 const matches=cloudRows.filter(x=>x?.name==='BURIMUNSI_DEFAULT_STAFF_PIN');
 if(matches.length!==1||matches[0].value!==sha(pin))throw Error('default_staff_pin_unconfirmed');
 return true;
}

export async function applyInitialBootstrapInFencedTransaction(client,prepared){
 if(!(prepared instanceof InitialBootstrapInput)||!client||typeof client.query!=='function')throw Error('bootstrap_input_invalid');
 const sql=await readFile(new URL('./initial-account-bootstrap.sql',import.meta.url),'utf8');
 if(sha(sql)!==INITIAL_BOOTSTRAP_SQL_SHA256)throw Error('bootstrap_sql_changed');
 const r=prepared.row();
 try{
  await client.query(`CREATE TEMP TABLE collect_initial_account_input(operation_id uuid NOT NULL,fence_operation_id uuid NOT NULL,
   epoch bigint NOT NULL,source_sha256 text NOT NULL,authorization_sha256 text NOT NULL,owner_principal_id text NOT NULL,
   collection_id text NOT NULL,admin_account_id uuid NOT NULL,staff_account_id uuid NOT NULL,admin_phone text NOT NULL,
   staff_phone text NOT NULL,admin_pin_hash jsonb NOT NULL,staff_pin_hash jsonb NOT NULL,pepper_id text NOT NULL) ON COMMIT DROP`);
  await client.query(`INSERT INTO pg_temp.collect_initial_account_input VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12::jsonb,$13::jsonb,$14)`,
   [r.operationId,r.fenceOperationId,r.epoch,r.sourceSha256,r.authorizationSha256,r.ownerPrincipalId,r.collectionId,
    r.adminAccountId,r.staffAccountId,r.adminPhone,r.staffPhone,JSON.stringify(r.adminPinHash),JSON.stringify(r.staffPinHash),r.pepperId]);
  await client.query(sql);await client.query('DROP TABLE pg_temp.collect_initial_account_input');
  return {operationId:r.operationId,applied:true,credentialValuesDisclosed:false};
 }catch(error){const e=Error('initial_account_bootstrap_failed');e.code=error?.code;throw e;}
}
