import test from 'node:test';import assert from 'node:assert/strict';import {createHash} from 'node:crypto';
import {canonicalProfile} from '../../supabase/functions/_shared/deployment-profile.js';
import {schedulerDeployment,loadConfig,renderSql,validateConnection} from '../supabase/jobs_config.mjs';
const profile={format:'collect.deployment.v1',id:'collect-local',mode:'self_hosted',environment:'qualification',supabase_origin:'https://supabase.collect.example',member_api_origin:'https://api.collect.example',admin_origin:'https://admin.collect.example',public_origin:'https://collect.example',google_callback_origin:'https://admin.collect.example'};
const raw=canonicalProfile(profile),bound={COLLECT_DEPLOYMENT_PROFILE:raw,COLLECT_DEPLOYMENT_PROFILE_SHA256:createHash('sha256').update(raw).digest('hex')};
test('scheduler endpoint binds to canonical self-hosted profile without changing native maintenance budget',async()=>{
 const saved={...process.env};try{
  Object.assign(process.env,bound,{COLLECT_DB_CA_PEM:'-----BEGIN CERTIFICATE-----\nAA==\n-----END CERTIFICATE-----'});
  assert.equal(schedulerDeployment().endpoint,profile.supabase_origin+'/functions/v1/collect-jobs');
  const config=await loadConfig(),rendered=await renderSql(config);
  assert.equal(config.deployment_profile_sha256,bound.COLLECT_DEPLOYMENT_PROFILE_SHA256);assert.equal(config.budgets.max_dispatches_per_utc_month,10000);assert.match(rendered.sql,/https:\/\/supabase\.collect\.example\/functions\/v1\/collect-jobs/);assert.doesNotMatch(rendered.sql,/https:\/\/rrlduytparvsjfmegalh\.supabase\.co/);
 }finally{for(const key of Object.keys(process.env))if(!(key in saved))delete process.env[key];Object.assign(process.env,saved);}
});
test('scheduler rejects a mismatched or unbound explicit profile',()=>{
 assert.throws(()=>schedulerDeployment({...bound,COLLECT_DEPLOYMENT_PROFILE_SHA256:'f'.repeat(64)}));
 assert.throws(()=>schedulerDeployment({COLLECT_DEPLOYMENT_PROFILE:raw}));
 assert.equal(schedulerDeployment({}).selfHosted,false);
});
