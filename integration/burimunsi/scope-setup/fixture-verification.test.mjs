// Host-only fixture integrity proof. Actual SQL/RLS is qualified separately on
// the isolated PostgreSQL clone; no database, provider or real credential here.
import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {decrypt} from '../../../supabase/functions/_shared/domain/encryption.js';
import {canonicalJson,sha256} from '../../../supabase/functions/_shared/domain/burimunsi/values.js';
const root=fileURLToPath(new URL('../../../',import.meta.url));
const output=JSON.parse(execFileSync(process.execPath,['supabase/tests/burimunsi/compile-scope-setup-fixture.mjs'],
 {cwd:root,encoding:'utf8',timeout:30000,maxBuffer:1024*1024}));
assert.equal(output.format,'collect.burimunsi.scope-setup-sql-fixture.v1');
assert.equal(output.production_acceptance,false);
const literal=output.setup_inputs.match(/set_config\('burimunsi\.setup\.fixture','((?:[^']|'')*)',true\)/);
assert(literal,'Expected the source compiler fixture literal');
const fixture=JSON.parse(literal[1].replaceAll("''","'"));
const custody={DATA_KEY_ID:'qualification-setup-only',DATA_ENCRYPTION_KEY:Buffer.alloc(32,83).toString('base64')};

test('independent wrong-custodian input has a genuine matching encrypted source handoff',async()=>{
 const {command,delivery,fingerprint}=fixture.wrongCustodian;
 assert.equal(command.installationId,fixture.activate.command.installationId);
 assert.equal(command.grantId,fixture.activate.command.grantId);
 assert.notEqual(command.custodianAccountId,fixture.activate.command.custodianAccountId);
 assert.equal(delivery.binding.custodianAccountId,command.custodianAccountId);
 assert.equal(delivery.binding.requestId,command.requestId);
 assert.equal(delivery.binding.expectedScopeVersion,command.expectedScopeVersion);
 assert.equal(fingerprint,await sha256(canonicalJson(command)));
 const code=new TextDecoder('utf-8',{fatal:true}).decode(await decrypt(custody,delivery.ciphertext,
  'burimunsi-scope-pair-v1:'+canonicalJson(delivery.binding)));
 assert(/^[a-f0-9]{64}$/.test(code),'Source-generated synthetic challenge format mismatch');
 assert.equal(await sha256(code),delivery.codeHash);
 assert(!output.setup_inputs.includes(code),'Plaintext synthetic challenge must not enter the SQL fixture');
});

test('a tuple mismatch is distinct from the valid wrong-custodian authority case',async()=>{
 const changed={...fixture.activate.command,custodianAccountId:fixture.wrongCustodian.command.custodianAccountId};
 assert.notEqual(changed.custodianAccountId,fixture.activate.delivery.binding.custodianAccountId);
 assert.equal(fixture.wrongCustodian.command.custodianAccountId,fixture.wrongCustodian.delivery.binding.custodianAccountId);
 const altered={...fixture.wrongCustodian.delivery.binding,custodianAccountId:fixture.activate.command.custodianAccountId};
 await assert.rejects(decrypt(custody,fixture.wrongCustodian.delivery.ciphertext,'burimunsi-scope-pair-v1:'+canonicalJson(altered)));
});
