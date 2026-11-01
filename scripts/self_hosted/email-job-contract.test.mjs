import test from 'node:test';
import assert from 'node:assert/strict';
import {parseEmailJobDispatch,emailJobResult} from '../../supabase/functions/_shared/email-job-contract.js';
const dispatch={dispatch_id:'e419b805-040e-4a03-a568-1e9edcdd4c80',email_admission:{contract:'collect.contribution-email.v1',source_sha256:'a'.repeat(64),approval_sha256:'b'.repeat(64),admitted_from:1793491200,batch_limit:1}};
test('email wake-ups cannot add recipients, expand batches or change admission shape',()=>{
 assert.equal(parseEmailJobDispatch(dispatch).dispatchId,dispatch.dispatch_id);
 for(const value of [[],{...dispatch,recipient:'not-a-client-input'}, {...dispatch,email_admission:{...dispatch.email_admission,batch_limit:2}}, {...dispatch,email_admission:{...dispatch.email_admission,source_sha256:'wrong'}}, {...dispatch,email_admission:{...dispatch.email_admission,recipient:'no'}}, {...dispatch,dispatch_id:null}])assert.throws(()=>parseEmailJobDispatch(value));
});
test('email operational replies redact destinations and never imply delivery',()=>{
 assert.deepEqual(emailJobResult({status:'complete',processed:1,results:[{state:'accepted',email:'synthetic@example.test',delivery_confirmed:true}]}),{status:'complete',processed:1,results:[{state:'accepted',delivery_confirmed:false}]});
 assert.equal(emailJobResult({status:'complete',processed:2,results:[]}).status,'unconfirmed');
 assert.equal(emailJobResult({status:'complete',processed:1,results:[{state:'delivered'}]}).status,'unconfirmed');
});
